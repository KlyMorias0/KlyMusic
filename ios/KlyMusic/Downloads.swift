import Foundation
import AVFoundation
import AudioToolbox
import Network

/// Some fragmented AAC containers report their duration twice to AVFoundation.
/// A complete PCM decode distinguishes that metadata issue from a different recording.
enum DownloadAudioContainer {
    static func verifiedDuration(at url: URL, expected: Double) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let reported = try await asset.load(.duration).seconds
        guard reported.isFinite, reported > 0 else { throw APIError.invalidResponse }
        guard expected.isFinite, expected > 0,
              !NativeCatalog.durationCompatible(expected: expected, actual: reported) else { return reported }

        let worker = Task.detached(priority: .utility) { try await decodedDuration(at: url) }
        let decoded = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        try Task.checkCancellation()
        guard NativeCatalog.durationCompatible(expected: expected, actual: decoded) else {
            throw APIError.server(L("İndirilen dosya bu şarkının süresiyle eşleşmiyor. Yeniden indir."))
        }

        let normalized = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".normalized.m4a")
        defer { try? FileManager.default.removeItem(at: normalized) }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw APIError.invalidResponse
        }
        exporter.outputURL = normalized
        exporter.outputFileType = .m4a
        // Export the complete recording. Never shorten media to make a duration check pass.
        await exporter.export()
        try Task.checkCancellation()
        guard exporter.status == .completed else { throw exporter.error ?? APIError.invalidResponse }
        let repaired = AVURLAsset(url: normalized)
        let repairedDuration = try await repaired.load(.duration).seconds
        guard try await repaired.load(.isPlayable),
              NativeCatalog.durationCompatible(expected: expected, actual: repairedDuration),
              NativeCatalog.durationCompatible(expected: decoded, actual: repairedDuration) else {
            throw APIError.invalidResponse
        }
        try Task.checkCancellation()
        _ = try FileManager.default.replaceItemAt(url, withItemAt: normalized)
        return repairedDuration
    }

    private static func decodedDuration(at url: URL) async throws -> Double {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard tracks.count == 1, let track = tracks.first else { throw APIError.invalidResponse }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw APIError.invalidResponse }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? APIError.invalidResponse }
        defer { if reader.status == .reading { reader.cancelReading() } }
        var seconds = 0.0
        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let format = CMSampleBufferGetFormatDescription(buffer),
                  let description = CMAudioFormatDescriptionGetStreamBasicDescription(format),
                  description.pointee.mSampleRate.isFinite, description.pointee.mSampleRate > 0 else {
                throw APIError.invalidResponse
            }
            seconds += Double(CMSampleBufferGetNumSamples(buffer)) / description.pointee.mSampleRate
        }
        guard reader.status == .completed, seconds.isFinite, seconds > 0 else {
            throw reader.error ?? APIError.invalidResponse
        }
        return seconds
    }
}

private actor DownloadResolveGate {
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func acquire() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiting.append($0) }
    }
    func release() {
        if waiting.isEmpty { busy = false }
        else { waiting.removeFirst().resume() }
    }
}

struct DownloadJob {
    var progress: Double = 0
    var status: String = L("Hazırlanıyor")
    var paused = false
    var failed = false
}

@MainActor final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()
    @Published var jobs: [String: DownloadJob] = [:]
    @Published var cellular = false
    weak var library: LibraryStore?
    var backgroundCompletion: (() -> Void)?
    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var preparing: [String: UUID] = [:]
    private var preparationTasks: [String: Task<Void, Never>] = [:]
    private var requests: [String: UUID] = [:]
    private var ignoredTaskIDs: Set<Int> = []
    private nonisolated let delegateProcessing = DispatchGroup()
    private let resolveGate = DownloadResolveGate()
    private let resolver: (Track, String) async throws -> PlaybackAsset
    private let validateAudio: (URL) async throws -> Bool
    private let monitor = NWPathMonitor()
    private lazy var session: URLSession = {
        #if targetEnvironment(simulator)
        // The VM's simulator download daemon cannot validate the local app signature.
        let config = URLSessionConfiguration.default
        #else
        let config = URLSessionConfiguration.background(withIdentifier: (Bundle.main.bundleIdentifier ?? "com.klymusic.app") + ".downloads")
        config.sessionSendsLaunchEvents = true
        #endif
        config.httpMaximumConnectionsPerHost = 2
        config.isDiscretionary = false
        config.timeoutIntervalForResource = 3600
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    init(validator: @escaping (URL) async throws -> Bool = { try await AVURLAsset(url: $0).load(.isPlayable) },
         resolver: @escaping (Track, String) async throws -> PlaybackAsset = { try await API.shared.resolve($0, quality: $1) }) {
        self.resolver = resolver
        validateAudio = validator
        super.init()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.cellular = path.isExpensive }
        }
        monitor.start(queue: DispatchQueue(label: "KlyMusic.Network"))
    }
    func reconnect() {
        session.getAllTasks { tasks in
            Task { @MainActor in
                for case let task as URLSessionDownloadTask in tasks {
                    guard let id = task.taskDescription, task.state != .completed, task.state != .canceling else { continue }
                    _ = self.adoptIfCurrent(task, id: id)
                }
            }
        }
    }
    // A relaunched session can deliver its completed task before getAllTasks returns.
    // Adopt that task from the persisted library, without reviving a cancelled or replaced one.
    private func adoptIfCurrent(_ task: URLSessionDownloadTask, id: String) -> Bool {
        guard !ignoredTaskIDs.contains(task.taskIdentifier), jobs[id]?.paused != true else { return false }
        if let current = tasks[id] { return current.taskIdentifier == task.taskIdentifier }
        guard jobs[id] == nil, preparing[id] == nil, requests[id] == nil,
              task.state != .canceling, library?.saved.contains(where: { $0.id == id }) == true,
              library?.localURL(id) == nil else { return false }
        tasks[id] = task
        if jobs[id] == nil { jobs[id] = DownloadJob(status: L("İndiriliyor")) }
        return true
    }
    func enqueue(_ track: Track) {
        guard library?.localURL(track.id) == nil, tasks[track.id] == nil, preparing[track.id] == nil else { return }
        _ = library?.record(track); library?.commit()
        let token = UUID()
        requests[track.id] = token; preparing[track.id] = token; jobs[track.id] = DownloadJob()
        preparationTasks[track.id] = Task {
            await resolveGate.acquire()
            defer {
                if preparing[track.id] == token {
                    preparing[track.id] = nil; preparationTasks[track.id] = nil
                }
                Task { await resolveGate.release() }
            }
            guard requests[track.id] == token, jobs[track.id] != nil, jobs[track.id]?.paused != true, !Task.isCancelled else { return }
            do {
                let wifiOnly = UserDefaults.standard.object(forKey: "wifiOnly") as? Bool ?? true
                let asset = try await resolver(track, PlaybackPreferences.quality())
                try Task.checkCancellation()
                guard requests[track.id] == token, jobs[track.id] != nil, jobs[track.id]?.paused != true, !Task.isCancelled else { return }
                var request = URLRequest(url: try API.mediaURL(asset))
                // Persist the verified duration before a background task can outlive
                // this process. Existing positive catalogue durations remain authoritative.
                if asset.duration.isFinite, asset.duration > 0 {
                    var verified = track
                    if !verified.duration.isFinite || verified.duration <= 0 { verified.duration = asset.duration }
                    _ = library?.record(verified); library?.commit()
                }
                // Some media CDNs throttle an unbounded GET; a full byte range uses their media path.
                request.setValue("bytes=0-", forHTTPHeaderField: "Range")
                request.allowsCellularAccess = !wifiOnly
                let resumeURL = MusicFiles.root.appendingPathComponent(MusicFiles.filename(track.id) + ".resume")
                let task: URLSessionDownloadTask
                if let data = try? Data(contentsOf: resumeURL) {
                    task = session.downloadTask(withResumeData: data)
                    try? FileManager.default.removeItem(at: resumeURL)
                } else { task = session.downloadTask(with: request) }
                task.taskDescription = track.id
                tasks[track.id] = task
                jobs[track.id] = DownloadJob(status: wifiOnly && cellular ? L("Wi-Fi bekleniyor") : L("İndiriliyor"))
                task.resume()
            } catch {
                guard requests[track.id] == token, jobs[track.id] != nil, !Task.isCancelled else { return }
                jobs[track.id] = DownloadJob(status: error.localizedDescription, failed: true)
            }
        }
    }
    func pause(_ id: String) {
        if let task = tasks[id] { ignoredTaskIDs.insert(task.taskIdentifier) }
        requests[id] = nil; preparing[id] = nil
        preparationTasks[id]?.cancel(); preparationTasks[id] = nil
        jobs[id]?.paused = true; jobs[id]?.status = L("Duraklatıldı")
        tasks[id]?.cancel(byProducingResumeData: { data in
            guard let data else { return }
            Task { @MainActor in
                guard self.jobs[id]?.paused == true, self.tasks[id] == nil else { return }
                try? data.write(to: MusicFiles.root.appendingPathComponent(MusicFiles.filename(id) + ".resume"), options: .atomic)
            }
        })
        tasks[id] = nil
    }
    func cancel(_ id: String) {
        if let task = tasks[id] { ignoredTaskIDs.insert(task.taskIdentifier) }
        requests[id] = nil; preparing[id] = nil
        preparationTasks[id]?.cancel(); preparationTasks[id] = nil
        tasks[id]?.cancel(); tasks[id] = nil; jobs[id] = nil
        try? FileManager.default.removeItem(at: MusicFiles.root.appendingPathComponent(MusicFiles.filename(id) + ".resume"))
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        Task { @MainActor in
            if self.jobs[id] != nil, self.tasks[id]?.taskIdentifier == downloadTask.taskIdentifier {
                self.jobs[id]?.progress = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
                self.jobs[id]?.status = L("İndiriliyor")
            }
        }
    }
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        // Register before returning to the serial delegate queue, rather than after a Task hop.
        delegateProcessing.enter()
        let stage = MusicFiles.downloads.appendingPathComponent(MusicFiles.filename(id) + "." + UUID().uuidString + ".staging.m4a")
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200 || response.statusCode == 206,
                  !(response.mimeType ?? "").contains("json"), !(response.mimeType ?? "").contains("text") else { throw APIError.invalidResponse }
            try? FileManager.default.removeItem(at: stage)
            try FileManager.default.moveItem(at: location, to: stage)
            Task { @MainActor in
                defer { self.delegateProcessing.leave() }
                do {
                    guard self.adoptIfCurrent(downloadTask, id: id) else { try? FileManager.default.removeItem(at: stage); return }
                    guard try await self.validateAudio(stage) else { throw APIError.invalidResponse }
                    let expectedDuration = self.library?.saved.first(where: { $0.id == id })?.track?.duration ?? 0
                    let actualDuration = try await DownloadAudioContainer.verifiedDuration(at: stage, expected: expectedDuration)
                    // Both validation loads suspend; a pause, cancel or replacement may have happened meanwhile.
                    guard self.jobs[id] != nil, self.jobs[id]?.paused != true, self.tasks[id]?.taskIdentifier == downloadTask.taskIdentifier else { try? FileManager.default.removeItem(at: stage); return }
                    guard var track = self.library?.saved.first(where: { $0.id == id })?.track else { throw APIError.invalidResponse }
                    if track.duration.isFinite, track.duration > 0 {
                        guard NativeCatalog.durationCompatible(expected: track.duration, actual: actualDuration) else {
                            throw APIError.server(L("İndirilen dosya bu şarkının süresiyle eşleşmiyor. Yeniden indir."))
                        }
                    } else {
                        // Legacy tasks may have no catalogue duration. Preserve their
                        // successful download, while recording the measured file duration.
                        track.duration = actualDuration
                    }
                    let filename = MusicFiles.filename(id) + ".m4a"
                    let destination = MusicFiles.downloads.appendingPathComponent(filename)
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: stage, to: destination)
                    self.library?.markDownloaded(track, filename: filename)
                    self.jobs[id] = nil; self.tasks[id] = nil; self.requests[id] = nil
                    // Optional metadata must not keep the system's completion handler waiting on the network.
                    Task {
                        if var lyrics = try? await API.shared.lyrics(track), lyrics.hasContent {
                            let file = MusicFiles.lyrics(id)
                            if lyrics.lines.isEmpty, let data = try? Data(contentsOf: file),
                               let saved = LyricsCacheEntry.decode(data), !saved.response.lines.isEmpty {
                                lyrics = saved.response
                            }
                            let entry = LyricsCacheEntry(response: lyrics, fetchedAt: .now)
                            if let data = try? JSONEncoder().encode(entry) { try? data.write(to: file, options: .atomic) }
                        }
                        await ArtworkCache.shared.pin(track.artworkURL)
                    }
                } catch {
                    try? FileManager.default.removeItem(at: stage)
                    guard self.jobs[id] != nil, self.jobs[id]?.paused != true, self.tasks[id]?.taskIdentifier == downloadTask.taskIdentifier else { return }
                    self.tasks[id] = nil
                    self.jobs[id] = DownloadJob(status: error.localizedDescription, failed: true)
                }
            }
        } catch {
            Task { @MainActor in
                defer { self.delegateProcessing.leave() }
                guard self.adoptIfCurrent(downloadTask, id: id) else { return }
                self.jobs[id] = DownloadJob(status: error.localizedDescription, failed: true); self.tasks[id] = nil
            }
        }
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let task = task as? URLSessionDownloadTask, let id = task.taskDescription, let error else { return }
        delegateProcessing.enter()
        let ns = error as NSError
        Task { @MainActor in
            defer { self.delegateProcessing.leave() }
            guard ns.code != NSURLErrorCancelled || self.tasks[id]?.taskIdentifier == task.taskIdentifier,
                  self.adoptIfCurrent(task, id: id) else { return }
            if ns.code != NSURLErrorCancelled, self.jobs[id] != nil {
                if let resume = ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                    try? resume.write(to: MusicFiles.root.appendingPathComponent(MusicFiles.filename(id) + ".resume"), options: .atomic)
                }
                self.jobs[id] = DownloadJob(status: error.localizedDescription, failed: true)
            }
            if self.tasks[id]?.taskIdentifier == task.taskIdentifier { self.tasks[id] = nil }
        }
    }
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            let completion = self.backgroundCompletion
            self.backgroundCompletion = nil
            self.delegateProcessing.notify(queue: .main) { completion?() }
        }
    }
}

/// Inspect only the container header and stop the transfer even when a CDN ignores Range.
final class AudioHeaderProbe: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Error>?
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var header = Data()
    private var finished = false

    static func check(_ request: URLRequest, configuration: URLSessionConfiguration) async throws -> Bool {
        let probe = AudioHeaderProbe()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                probe.start(request, configuration: configuration, continuation: continuation)
            }
        } onCancel: { probe.finish(.failure(CancellationError())) }
    }

    private func start(_ request: URLRequest, configuration: URLSessionConfiguration,
                       continuation: CheckedContinuation<Bool, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); continuation.resume(throwing: CancellationError()); return }
        self.continuation = continuation
        guard let url = request.url, NativeCatalog.allowedMediaURL(url) else {
            lock.unlock(); finish(.success(false)); return
        }
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        self.session = session; self.task = task
        task.resume()
        lock.unlock()
    }

    private func finish(_ result: Result<Bool, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation, session = self.session, task = self.task
        self.continuation = nil; self.session = nil; self.task = nil
        lock.unlock()
        task?.cancel(); session?.invalidateAndCancel()
        continuation?.resume(with: result)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let url = http.url, NativeCatalog.allowedMediaURL(url) else {
            completionHandler(.cancel); finish(.success(false)); return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        header.append(contentsOf: data.prefix(max(0, 12 - header.count)))
        let complete = header.count == 12
        let valid = complete && String(data: header.subdata(in: 4..<8), encoding: .ascii) == "ftyp"
        lock.unlock()
        if complete { finish(.success(valid)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, NativeCatalog.allowedMediaURL(url) else {
            completionHandler(nil); finish(.success(false)); return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
        else { finish(.success(false)) }
    }
}
