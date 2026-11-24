import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: MusicPlayer
    @AppStorage("quality") private var quality = "auto"
    @AppStorage("lowDataMode") private var lowData = true
    @AppStorage("wifiOnly") private var wifiOnly = true
    @AppStorage("autoDownloadFavorites") private var autoDownloadFavorites = false
    @AppStorage("theme") private var theme = "dark"
    @AppStorage("language") private var language = "system"
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled = true
    @AppStorage("dolbyAtmosMode") private var dolbyAtmosMode = "auto"
    @AppStorage("crossfadeEnabled") private var crossfadeEnabled = false
    @AppStorage("crossfadeSeconds") private var crossfadeSeconds = 4.0
    @State private var status: String?
    @State private var document = BackupDocument()
    @State private var exporting = false
    @State private var importing = false
    @State private var eraseHistory = false

    private let themeOptions: [SettingsChoice] = [
        .init(title: "Sistem", value: "system"),
        .init(title: "Açık", value: "light"),
        .init(title: "Koyu", value: "dark")
    ]
    private let languageOptions: [SettingsChoice] = [
        .init(title: "Sistem", value: "system"),
        .init(title: "Türkçe", value: "tr"),
        .init(title: "English", value: "en")
    ]
    private var selection: String { lowData ? "data" : (quality == "high" ? "high" : "auto") }

    private var currentQualityTitle: String {
        if lowData { return L("Veri Tasarrufu") }
        if quality == "high" { return L("Yüksek kalite") }
        return L("Otomatik")
    }

    private var currentThemeTitle: String {
        L(themeOptions.first { $0.value == theme }?.title ?? "Sistem")
    }

    private var currentLanguageTitle: String {
        L(languageOptions.first { $0.value == language }?.title ?? "Sistem")
    }

    private var currentDolbyAtmosTitle: String {
        switch dolbyAtmosMode {
        case "alwaysOn": return L("Her Zaman Açık")
        case "off": return L("Kapalı")
        default: return L("Otomatik")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        List {
            Section {
                accountHeaderCard
                    .listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
            }
            .listRowBackground(Color.musicElevated)

            Section {
                NavigationLink {
                    DynamicIslandSettingsView()
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "platter.filled.top.iphone", color: Color(red: 0.35, green: 0.34, blue: 0.84))
                        Text(L("Dynamic Island ve Canlı Etkinlik"))
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.86)
                        Spacer(minLength: 8)
                        SettingsValueText(text: liveActivityEnabled ? L("Açık") : L("Kapalı"))
                    }
                    .frame(minHeight: 34)
                }
                .accessibilityIdentifier("settings.dynamicIsland")
                .accessibilityValue(liveActivityEnabled ? L("Açık") : L("Kapalı"))
                .settingsCompactRowInsets()

                NavigationLink {
                    DolbyAtmosSettingsView()
                } label: {
                    HStack(spacing: 12) {
                        SettingsDolbyTile()
                        Text(L("Dolby Atmos"))
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        SettingsValueText(text: currentDolbyAtmosTitle)
                    }
                    .frame(minHeight: 34)
                }
                .accessibilityIdentifier("settings.dolbyAtmos")
                .accessibilityValue(currentDolbyAtmosTitle)
                .settingsCompactRowInsets()

                NavigationLink {
                    AudioQualitySettings(quality: $quality, lowData: $lowData)
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "headphones", color: Color(red: 0.76, green: 0.38, blue: 0.54))
                        Text(L("Ses kalitesi"))
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        SettingsValueText(text: currentQualityTitle)
                    }
                    .frame(minHeight: 34)
                }
                .accessibilityIdentifier("settings.quality")
                .accessibilityValue(currentQualityTitle)
                .settingsCompactRowInsets()

                NavigationLink {
                    PlaybackSettingsView()
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "slider.horizontal.3", color: Color.coral)
                        Text(L("Geçiş ve Oynatma"))
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        if crossfadeEnabled {
                            SettingsValueText(text: String(format: L("%lld sn"), Int64(crossfadeSeconds.rounded())))
                        }
                    }
                    .frame(minHeight: 34)
                }
                .accessibilityIdentifier("settings.playback")
                .settingsCompactRowInsets()
            } header: {
                Text(L("Dinleme ve Ses"))
            }
            .listRowBackground(Color.musicElevated)

            Section {
                Toggle(isOn: $wifiOnly) {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "wifi", color: Color(red: 0.20, green: 0.68, blue: 0.42))
                        Text(L("Yalnızca Wi-Fi ile indir"))
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                    .frame(minHeight: 34)
                }
                .tint(Color.coral)
                .accessibilityIdentifier("settings.wifiOnly")
                .settingsCompactRowInsets()

                Toggle(isOn: $autoDownloadFavorites) {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "star.fill", color: Color(red: 0.95, green: 0.55, blue: 0.15))
                        Text(L("Favorileri Otomatik İndir"))
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                    .frame(minHeight: 34)
                }
                .tint(Color.coral)
                .accessibilityIdentifier("settings.autoDownloadFavorites")
                .settingsCompactRowInsets()

                NavigationLink {
                    DownloadsView()
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "arrow.down.circle.fill", color: Color(red: 0.15, green: 0.50, blue: 0.95))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(L("İndirilen Müzikler"))
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            if !library.downloaded.isEmpty {
                                Text(String(format: L("%lld şarkı"), Int64(library.downloaded.count)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        SettingsValueText(text: storageSize)
                    }
                    .frame(minHeight: 34)
                }
                .accessibilityIdentifier("settings.downloads")
                .accessibilityValue(storageSize)
                .settingsCompactRowInsets()
            } header: {
                Text(L("İndirilenler"))
            }
            .listRowBackground(Color.musicElevated)

            Section {
                NavigationLink {
                    SettingsChoiceView(title: "Görünüm", selection: $theme, options: themeOptions, identifier: "settings.theme")
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "moon.fill", color: Color(red: 0.38, green: 0.38, blue: 0.70))
                        Text(L("Görünüm"))
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        SettingsValueText(text: currentThemeTitle)
                    }
                    .frame(minHeight: 34)
                }
                .accessibilityIdentifier("settings.theme")
                .accessibilityValue(currentThemeTitle)
                .settingsCompactRowInsets()

                NavigationLink {
                    SettingsChoiceView(title: "Dil", selection: $language, options: languageOptions, identifier: "settings.language")
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "globe", color: Color(red: 0.18, green: 0.65, blue: 0.72))
                        Text(L("Dil"))
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        SettingsValueText(text: currentLanguageTitle)
                    }
                    .frame(minHeight: 34)
                }
                .accessibilityIdentifier("settings.language")
                .accessibilityValue(currentLanguageTitle)
                .settingsCompactRowInsets()
            } header: {
                Text(L("Görünüm"))
            }
            .listRowBackground(Color.musicElevated)

            Section {
                NavigationLink {
                    dataSettings
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "internaldrive.fill", color: Color(red: 0.95, green: 0.55, blue: 0.15))
                        Text(L("Kütüphane ve Veriler"))
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(minHeight: 34)
                }
                .accessibilityIdentifier("settings.data")
                .settingsCompactRowInsets()
            } header: {
                Text(L("Kütüphane"))
            }
            .listRowBackground(Color.musicElevated)

            Section {
                NavigationLink {
                    aboutSettings
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "info.circle.fill", color: Color(red: 0.50, green: 0.52, blue: 0.58))
                        Text(L("Hakkında"))
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    .frame(minHeight: 34)
                }
                .accessibilityIdentifier("settings.about")
                .settingsCompactRowInsets()
            } header: {
                Text(L("Hakkında"))
            } footer: {
                Text(String(format: L("Sürüm %@ (%@) · %lld şarkı · %lld liste"), appVersion, appBuild, Int64(library.saved.count), Int64(library.playlists.count)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            }
            .listRowBackground(Color.musicElevated)

            if let status {
                Section {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.status")
                }
                .listRowBackground(Color.musicElevated)
            }
        }
        .musicSettingsList(sectionSpacing: 14)
        .environment(\.defaultMinListRowHeight, 44)
        .navigationTitle(L("Ayarlar"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.pageBackground, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Bitti")) { dismiss() }
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.coral)
            }
        }
        .onChange(of: selection) { _, _ in player.refreshPreparation() }
    }

    private var accountHeaderCard: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.34, blue: 0.44), Color.coral, Color(red: 0.85, green: 0.16, blue: 0.34)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(.white.opacity(0.20), lineWidth: 0.6)
                    }
                Image(systemName: "music.note")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 50, height: 50)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text("KlyMusic")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if dolbyAtmosMode != "off" {
                        DolbyAtmosBadge(color: .secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                            .accessibilityHidden(true)
                    }
                }

                Text(String(format: L("%lld şarkı · %lld liste"), Int64(library.saved.count), Int64(library.playlists.count)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var dataSettings: some View {
        List {
            Section {
                Button {
                    do {
                        document = BackupDocument(data: try library.backup())
                        exporting = true
                    } catch {
                        status = error.localizedDescription
                    }
                } label: {
                    HStack(spacing: 14) {
                        SettingsIconTile(symbol: "arrow.up.doc.fill", color: Color(red: 0.15, green: 0.50, blue: 0.95))
                        Text(L("Kütüphaneyi Yedekle"))
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("settings.backup")

                Button {
                    importing = true
                } label: {
                    HStack(spacing: 14) {
                        SettingsIconTile(symbol: "arrow.down.doc.fill", color: Color(red: 0.20, green: 0.68, blue: 0.42))
                        Text(L("Yedeği Geri Yükle"))
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("settings.restore")
            } footer: {
                SettingsNote(text: "Ses dosyaları yedeğe dahil edilmez.")
            }
            .listRowBackground(Color.musicElevated)

            Section {
                Button(role: .destructive) {
                    eraseHistory = true
                } label: {
                    HStack(spacing: 14) {
                        SettingsIconTile(symbol: "trash.fill", color: Color(red: 0.92, green: 0.26, blue: 0.21))
                        Text(L("Dinleme Geçmişini Temizle"))
                            .font(.body)
                            .foregroundStyle(.red)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("settings.eraseHistory")
            }
            .listRowBackground(Color.musicElevated)

            if let status {
                Section {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings.status")
                }
                .listRowBackground(Color.musicElevated)
            }
        }
        .musicSettingsList()
        .navigationTitle(L("Kütüphane ve Veriler"))
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "KlyMusic-Backup") { result in
            switch result {
            case .failure(let error): status = error.localizedDescription
            case .success: status = L("Kütüphane yedeklendi.")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let allowed = url.startAccessingSecurityScopedResource()
                defer { if allowed { url.stopAccessingSecurityScopedResource() } }
                try library.restore(Data(contentsOf: url))
                status = L("Kütüphane geri yüklendi.")
            } catch {
                status = error.localizedDescription
            }
        }
        .confirmationDialog(L("Dinleme geçmişi temizlensin mi?"), isPresented: $eraseHistory, titleVisibility: .visible) {
            Button(L("Geçmişi temizle"), role: .destructive) { library.removeHistory() }
        }
    }

    private var aboutSettings: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    SettingsIconTile(symbol: "app.badge.fill", color: Color.coral)
                    Text(L("Uygulama"))
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("KlyMusic")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)

                HStack(spacing: 14) {
                    SettingsIconTile(symbol: "number", color: Color(red: 0.50, green: 0.52, blue: 0.58))
                    Text(L("Sürüm"))
                        .font(.body)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(appVersion)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
            }
            .listRowBackground(Color.musicElevated)

            Section {
                NavigationLink {
                    ScrollView {
                        Text((Bundle.main.url(forResource: "ThirdPartyLicenses", withExtension: "txt").flatMap { try? String(contentsOf: $0) }) ?? "")
                            .font(.footnote)
                            .textSelection(.enabled)
                            .padding(20)
                    }
                    .background(Color.pageBackground)
                    .navigationTitle(L("Lisanslar"))
                } label: {
                    HStack(spacing: 14) {
                        SettingsIconTile(symbol: "doc.text.fill", color: Color(red: 0.38, green: 0.38, blue: 0.70))
                        Text(L("Lisanslar"))
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    .frame(minHeight: 44)
                }
            }
            .listRowBackground(Color.musicElevated)
        }
        .musicSettingsList()
        .navigationTitle(L("Hakkında"))
    }

    private var storageSize: String {
        let urls = (try? FileManager.default.contentsOfDirectory(at: MusicFiles.downloads, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let bytes = urls.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return bytes == 0 ? L("Yok") : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private enum IslandPreviewMode: String, CaseIterable, Identifiable {
    case compact
    case expanded
    case minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: return "Kompakt"
        case .expanded: return "Genişletilmiş"
        case .minimal: return "Minimal"
        }
    }
}

private struct IslandWaveformMetrics {
    let heights: [CGFloat]
    let opacities: [Double]

    static func compute(at date: Date, isActive: Bool, reduceMotion: Bool, maxBarHeight: CGFloat) -> IslandWaveformMetrics {
        let staticScales: [Double] = isActive ? [0.44, 0.86, 0.62, 0.94] : [0.28, 0.42, 0.34, 0.46]
        guard isActive && !reduceMotion else {
            return IslandWaveformMetrics(
                heights: staticScales.map { max(3, maxBarHeight * CGFloat($0)) },
                opacities: staticScales.map { isActive ? 0.95 : 0.45 + $0 * 0.35 }
            )
        }
        let t: Double = date.timeIntervalSinceReferenceDate
        let speeds: [Double] = [5.2, 6.9, 5.9, 7.8]
        let phases: [Double] = [0.0, 1.3, 2.5, 0.7]
        var heights: [CGFloat] = []
        var opacities: [Double] = []
        for idx in 0..<4 {
            let primary: Double = 0.5 + 0.5 * Foundation.sin(t * speeds[idx] + phases[idx])
            let secondary: Double = 0.5 + 0.5 * Foundation.cos(t * (speeds[idx] * 0.64) - phases[idx])
            let amplitude: Double = 0.24 + 0.76 * (0.65 * primary + 0.35 * secondary)
            heights.append(max(3, maxBarHeight * CGFloat(amplitude)))
            opacities.append(0.74 + 0.26 * amplitude)
        }
        return IslandWaveformMetrics(heights: heights, opacities: opacities)
    }
}

private struct IslandWaveformView: View {
    let isActive: Bool
    var barWidth: CGFloat = 2.4
    var spacing: CGFloat = 2.2
    var maxHeight: CGFloat = 14
    var color: Color = .coral
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: !isActive || reduceMotion)) { timeline in
            let metrics = IslandWaveformMetrics.compute(
                at: timeline.date,
                isActive: isActive,
                reduceMotion: reduceMotion,
                maxBarHeight: maxHeight
            )
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(color.opacity(metrics.opacities[index]))
                        .frame(width: barWidth, height: metrics.heights[index])
                }
            }
            .frame(height: maxHeight)
        }
        .accessibilityHidden(true)
    }
}

private struct DynamicIslandSettingsView: View {
    @EnvironmentObject private var player: MusicPlayer
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("liveActivityEnabled") private var liveActivityEnabled = true
    @AppStorage("islandTrailingStyle") private var islandTrailingStyle = "waveform"
    @AppStorage("inAppIslandEnabled") private var inAppIslandEnabled = false
    @AppStorage("dolbyAtmosMode") private var dolbyAtmosMode = "auto"
    @State private var previewMode: IslandPreviewMode = .expanded
    @State private var demoPlaying = true

    private var activeTrack: Track? { player.current ?? player.pendingTrack }

    private var effectiveIsPlaying: Bool {
        guard liveActivityEnabled else { return false }
        return activeTrack != nil ? player.isPlaying : demoPlaying
    }

    private var isBufferingActiveTrack: Bool {
        activeTrack != nil && (player.isBuffering || (player.current == nil && player.pendingTrack != nil))
    }

    private var stageBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.10, green: 0.10, blue: 0.13)
            : Color(red: 0.93, green: 0.94, blue: 0.97)
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    statusBarPreview

                    ZStack {
                        if previewMode == .expanded {
                            expandedIsland
                                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
                        } else if previewMode == .minimal {
                            minimalIsland
                                .transition(.opacity.combined(with: .scale(scale: 0.90, anchor: .top)))
                        } else {
                            compactIsland
                                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 176, alignment: .center)
                    .opacity(liveActivityEnabled ? 1.0 : 0.55)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleCompactAndExpanded()
                    }

                    modeSwitcher

                    Text(liveActivityEnabled ? L("Önizlemeye dokunarak genişletip daraltabilirsiniz.") : L("Canlı Etkinlik Kapalı"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 6)
            }
            .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
            .listRowBackground(
                ZStack {
                    stageBackground
                    if liveActivityEnabled {
                        RadialGradient(
                            colors: [Color.coral.opacity(colorScheme == .dark ? 0.18 : 0.12), .clear],
                            center: .center,
                            startRadius: 16,
                            endRadius: 170
                        )
                    }
                }
            )

            Section {
                Toggle(isOn: $liveActivityEnabled) {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "platter.filled.top.iphone", color: Color(red: 0.35, green: 0.34, blue: 0.84))
                        Text(L("Canlı Etkinlik ve Dynamic Island"))
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    .frame(minHeight: 44)
                }
                .tint(Color.coral)
                .accessibilityIdentifier("settings.dynamicIsland.liveActivity")

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "waveform", color: Color(red: 0.18, green: 0.65, blue: 0.72))
                        Text(L("Kompakt Sağ Alan"))
                            .font(.body)
                            .foregroundStyle(.primary)
                    }

                    Picker(L("Kompakt Sağ Alan"), selection: $islandTrailingStyle) {
                        Text(L("Ses Dalgası")).tag("waveform")
                        Text(L("Kalan Süre")).tag("timer")
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)

                Toggle(isOn: $inAppIslandEnabled) {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "sparkles", color: Color.coral)
                        Text(L("Uygulama İçi Dynamic Island"))
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    .frame(minHeight: 44)
                }
                .tint(Color.coral)
                .accessibilityIdentifier("settings.dynamicIsland.inApp")
            } footer: {
                SettingsNote(text: "Kilit ekranı ve üst adada çalan parçayı canlı olarak gösterir.")
            }
            .listRowBackground(Color.musicElevated)
        }
        .musicSettingsList()
        .navigationTitle(L("Dynamic Island ve Canlı Etkinlik"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusBarPreview: some View {
        HStack {
            Text("9:41")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
            Spacer()
            HStack(spacing: 5) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
            }
            .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(Color.primary.opacity(0.45))
        .padding(.horizontal, 10)
        .accessibilityHidden(true)
    }

    private var compactIsland: some View {
        HStack(spacing: 0) {
            islandArtwork(size: 22, cornerRadius: 5.5)
                .padding(.leading, 8)

            Spacer(minLength: 10)

            trueDepthLens

            Spacer(minLength: 10)

            Group {
                if islandTrailingStyle == "timer" {
                    Text("-2:18")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.coral)
                } else {
                    IslandWaveformView(
                        isActive: effectiveIsPlaying,
                        barWidth: 2.2,
                        spacing: 2.0,
                        maxHeight: 13,
                        color: .coral
                    )
                }
            }
            .padding(.trailing, 10)
        }
        .frame(width: 218, height: 37)
        .background(islandPillSurface(cornerRadius: 18.5))
    }

    private var minimalIsland: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                islandArtwork(size: 22, cornerRadius: 5.5)
                    .padding(.leading, 8)
                Spacer(minLength: 12)
                trueDepthLens
                    .padding(.trailing, 12)
            }
            .frame(width: 126, height: 37)
            .background(islandPillSurface(cornerRadius: 18.5))

            ZStack {
                Circle()
                    .fill(Color.black)
                    .overlay {
                        Circle()
                            .strokeBorder(islandGlassStroke, lineWidth: 0.85)
                    }
                    .shadow(color: .black.opacity(0.32), radius: 12, y: 5)

                if islandTrailingStyle == "timer" {
                    Text("2:18")
                        .font(.system(size: 9.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Color.coral)
                } else {
                    IslandWaveformView(
                        isActive: effectiveIsPlaying,
                        barWidth: 2.0,
                        spacing: 1.8,
                        maxHeight: 12,
                        color: .coral
                    )
                }
            }
            .frame(width: 37, height: 37)
        }
    }

    private var expandedIsland: some View {
        VStack(spacing: 13) {
            HStack(spacing: 12) {
                islandArtwork(size: 48, cornerRadius: 11)

                VStack(alignment: .leading, spacing: 2.5) {
                    Text(activeTrack?.title ?? L("Gece Yolu"))
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(activeTrack?.artist ?? L("KlyMusic Seçkisi"))
                        .font(.system(size: 12.5, weight: .regular))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)

                    if dolbyAtmosMode != "off" {
                        HStack(spacing: 4) {
                            DolbyDoubleDMark()
                                .fill(Color.white.opacity(0.75), style: FillStyle(eoFill: true))
                                .frame(width: 12, height: 8)
                                .accessibilityHidden(true)
                            Text("Dolby Atmos")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .padding(.top, 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                IslandWaveformView(
                    isActive: effectiveIsPlaying,
                    barWidth: 2.5,
                    spacing: 2.4,
                    maxHeight: 16,
                    color: .coral
                )
            }

            HStack(spacing: 8) {
                Text("1:24")
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.18))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.coral, Color(red: 1.0, green: 0.56, blue: 0.62)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * 0.38)
                    }
                    .frame(height: 4.5)
                    .frame(maxHeight: .infinity)
                }
                .frame(height: 10)

                Text("-2:18")
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
            }

            HStack(spacing: 36) {
                Button {
                    if activeTrack != nil { player.previous() }
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Önceki şarkı"))

                Button {
                    if activeTrack != nil {
                        player.toggle()
                    } else {
                        demoPlaying.toggle()
                    }
                } label: {
                    Group {
                        if isBufferingActiveTrack {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: effectiveIsPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 23, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 40, height: 32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(effectiveIsPlaying ? L("Duraklat") : L("Çal"))

                Button {
                    if activeTrack != nil { player.next() }
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("Sonraki şarkı"))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .frame(maxWidth: 336)
        .background(islandPillSurface(cornerRadius: 36))
    }

    private var modeSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(IslandPreviewMode.allCases) { mode in
                let selected = previewMode == mode
                Button {
                    selectPreviewMode(mode)
                } label: {
                    Text(L(mode.title))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selected ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(selected ? Color.coral : Color.primary.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.dynamicIsland.mode." + mode.rawValue)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var trueDepthLens: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color(red: 0.14, green: 0.18, blue: 0.30), Color(red: 0.03, green: 0.03, blue: 0.05)],
                    center: .center,
                    startRadius: 0.5,
                    endRadius: 5.5
                )
            )
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
            }
            .frame(width: 11, height: 11)
            .accessibilityHidden(true)
    }

    private var islandGlassStroke: LinearGradient {
        LinearGradient(
            colors: [.white.opacity(0.28), .white.opacity(0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func islandPillSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.black)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(islandGlassStroke, lineWidth: 0.85)
            }
            .shadow(color: .black.opacity(0.36), radius: 18, y: 8)
    }

    @ViewBuilder
    private func islandArtwork(size: CGFloat, cornerRadius: CGFloat) -> some View {
        if let track = activeTrack {
            Artwork(url: track.artwork, radius: cornerRadius)
                .frame(width: size, height: size)
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 1.0, green: 0.34, blue: 0.44), Color(red: 0.56, green: 0.15, blue: 0.42)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    private func toggleCompactAndExpanded() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78)) {
            previewMode = previewMode == .expanded ? .compact : .expanded
        }
    }

    private func selectPreviewMode(_ mode: IslandPreviewMode) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78)) {
            previewMode = mode
        }
    }
}

private struct DolbyAtmosSettingsView: View {
    @AppStorage("dolbyAtmosMode") private var dolbyAtmosMode = "auto"

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.16, green: 0.22, blue: 0.36), Color(red: 0.08, green: 0.10, blue: 0.18)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.6)
                            }
                        DolbyDoubleDMark()
                            .fill(.white, style: FillStyle(eoFill: true))
                            .frame(width: 26, height: 18)
                    }
                    .frame(width: 48, height: 48)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Uzamsal Ses ve Dolby Atmos"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(L("Desteklenen parçalarda üç boyutlu, derin ve sürükleyici bir ses sahnesi sunar."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.musicElevated)

            Section {
                modeRow(
                    title: "Otomatik",
                    value: "auto",
                    subtitle: "Kulaklık veya uyumlu hoparlör algılandığında Dolby Atmos etkinleşir."
                )
                modeRow(
                    title: "Her Zaman Açık",
                    value: "alwaysOn",
                    subtitle: "Desteklenen tüm parçalarda Dolby Atmos ses akışını zorlar."
                )
                modeRow(
                    title: "Kapalı",
                    value: "off",
                    subtitle: "Standart stereo ses çıkışını kullanır."
                )
            } footer: {
                SettingsNote(text: "Desteklenen kulaklıklarda en iyi deneyimi elde etmek için Otomatik önerilir.")
            }
            .listRowBackground(Color.musicElevated)
        }
        .musicSettingsList()
        .navigationTitle(L("Dolby Atmos"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func modeRow(title: String, value: String, subtitle: String) -> some View {
        let selected = dolbyAtmosMode == value
        return Button {
            dolbyAtmosMode = value
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L(title))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(L(subtitle))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.coral)
                    .frame(width: 22)
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(TrackRowButtonStyle())
        .accessibilityIdentifier("settings.dolbyAtmos." + value)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct PlaybackSettingsView: View {
    @AppStorage("crossfadeEnabled") private var crossfadeEnabled = false
    @AppStorage("crossfadeSeconds") private var crossfadeSeconds = 4.0
    @AppStorage("soundCheckEnabled") private var soundCheckEnabled = true
    @AppStorage("infiniteAutoplay") private var infiniteAutoplay = true
    @AppStorage("useListeningHistory") private var useListeningHistory = true
    @AppStorage("animatedArtwork") private var animatedArtwork = true

    var body: some View {
        List {
            Section {
                Toggle(isOn: $crossfadeEnabled.animation(.easeInOut(duration: 0.22))) {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "arrow.triangle.swap", color: Color.coral)
                        Text(L("Şarkılar Arası Geçiş (Crossfade)"))
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    .frame(minHeight: 44)
                }
                .tint(Color.coral)
                .accessibilityIdentifier("settings.playback.crossfade")

                if crossfadeEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L("Geçiş Süresi"))
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(String(format: L("%lld sn"), Int64(crossfadeSeconds.rounded())))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(Color.coral)
                        }
                        Slider(value: $crossfadeSeconds, in: 1...12, step: 1)
                            .tint(Color.coral)
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                Text(L("Geçiş"))
            } footer: {
                SettingsNote(text: "Bir şarkı biterken sonraki şarkıya kesintisiz yumuşak geçiş yapar.")
            }
            .listRowBackground(Color.musicElevated)

            Section {
                Toggle(isOn: $soundCheckEnabled) {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "speaker.wave.2.fill", color: Color(red: 0.20, green: 0.68, blue: 0.42))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Ses Düzeyini Eşitle"))
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(L("Tüm parçaların ses yüksekliğini otomatik olarak dengeler."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .tint(Color.coral)
                .accessibilityIdentifier("settings.playback.soundCheck")

                Toggle(isOn: $infiniteAutoplay) {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "infinity", color: Color(red: 0.95, green: 0.55, blue: 0.15))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Otomatik Çal"))
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(L("Sıra bittiğinde benzer şarkılarla çalmaya devam eder."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .tint(Color.coral)
                .accessibilityIdentifier("settings.playback.autoplay")
            } header: {
                Text(L("Ses ve Sıra"))
            }
            .listRowBackground(Color.musicElevated)

            Section {
                Toggle(isOn: $useListeningHistory) {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "clock.arrow.circlepath", color: Color(red: 0.18, green: 0.65, blue: 0.72))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Dinleme Geçmişini Kullan"))
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(L("Önerileri ve Son Çalınanlar listesini etkiler."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .tint(Color.coral)
                .accessibilityIdentifier("settings.playback.listeningHistory")

                Toggle(isOn: $animatedArtwork) {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "play.square.stack.fill", color: Color(red: 0.58, green: 0.34, blue: 0.88))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("Hareketli Kapak Görselleri"))
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(L("Albüm ve çalma listesi kapaklarını canlandırır."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 44)
                }
                .tint(Color.coral)
                .accessibilityIdentifier("settings.playback.animatedArtwork")
            } header: {
                Text(L("Kişiselleştirme ve Görseller"))
            }
            .listRowBackground(Color.musicElevated)
        }
        .musicSettingsList()
        .navigationTitle(L("Geçiş ve Oynatma"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsIconTile: View {
    let symbol: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                }
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}

private struct SettingsDolbyTile: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(red: 0.16, green: 0.22, blue: 0.34))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                }
            DolbyDoubleDMark()
                .fill(.white, style: FillStyle(eoFill: true))
                .frame(width: 17, height: 11.5)
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }
}

private struct SettingsValueText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsChoice {
    let title: String
    let value: String
}

private struct SettingsChoiceView: View {
    let title: String
    @Binding var selection: String
    let options: [SettingsChoice]
    let identifier: String

    var body: some View {
        List {
            Section {
                ForEach(options, id: \.value) { option in
                    Button {
                        selection = option.value
                    } label: {
                        HStack {
                            Text(L(option.title))
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 12)
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.coral)
                                .frame(width: 22)
                                .opacity(selection == option.value ? 1 : 0)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(TrackRowButtonStyle())
                    .accessibilityIdentifier(identifier + "." + option.value)
                    .accessibilityAddTraits(selection == option.value ? .isSelected : [])
                }
            }
            .listRowBackground(Color.musicElevated)
        }
        .musicSettingsList()
        .navigationTitle(L(title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsNote: View {
    let text: String
    var body: some View {
        Text(L(text))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
    }
}

private struct AudioQualitySettings: View {
    @Binding var quality: String
    @Binding var lowData: Bool
    @AppStorage("losslessEnabled") private var losslessEnabled = true

    var body: some View {
        List {
            Section {
                option("Otomatik", value: "auto", subtitle: "Ağın hızına göre en uygun kaliteyi seçer.", badge: "AAC · 160 kbps")
                option("Veri Tasarrufu", value: "data", subtitle: "Daha az internet kullanır.", badge: "AAC · 64 kbps")
                option("Yüksek kalite", value: "high", subtitle: "Kaynağın sunduğu yüksek kaliteli sesi kullanır.", badge: "Dolby Atmos · 256 kbps", showDolbyMark: true)
            } footer: {
                SettingsNote(text: "Yeni tercih sonraki parçada uygulanır. İnternet kullanımı kaynağa ve bit hızına bağlıdır.")
            }
            .listRowBackground(Color.musicElevated)

            Section {
                Toggle(isOn: $losslessEnabled) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(L("Kayıpsız Ses"))
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            HStack(spacing: 4) {
                                Image(systemName: "waveform")
                                    .font(.system(size: 9.5, weight: .semibold))
                                Text("24-bit/192 kHz ALAC / AAC")
                                    .font(.caption2.weight(.semibold))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                            .accessibilityHidden(true)
                        }
                        Text(L("Orijinal stüdyo kaydındaki tüm ses ayrıntılarını korur."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .tint(Color.coral)
                .accessibilityIdentifier("settings.lossless")
            } footer: {
                SettingsNote(text: "Kayıpsız ses daha fazla internet verisi ve depolama alanı kullanır.")
            }
            .listRowBackground(Color.musicElevated)
        }
        .musicSettingsList()
        .navigationTitle(L("Ses kalitesi"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func option(_ title: String, value: String, subtitle: String, badge: String, showDolbyMark: Bool = false) -> some View {
        let active = (value == "auto" && !lowData && (quality == "auto" || quality.isEmpty)) ||
                     (value == "data" && lowData) ||
                     (value == "high" && !lowData && quality == "high")
        return Button {
            quality = value
            lowData = value == "data"
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(L(title))
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        HStack(spacing: 4) {
                            if showDolbyMark {
                                DolbyDoubleDMark()
                                    .fill(Color.secondary, style: FillStyle(eoFill: true))
                                    .frame(width: 12, height: 8)
                            }
                            Text(badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .accessibilityHidden(true)
                    }
                    Text(L(subtitle))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.coral)
                    .frame(width: 22)
                    .opacity(active ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(TrackRowButtonStyle())
        .accessibilityIdentifier("settings.quality." + value)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private extension View {
    func musicSettingsList(sectionSpacing: CGFloat = 20) -> some View {
        self
            .listStyle(.insetGrouped)
            .listSectionSpacing(sectionSpacing)
            .scrollContentBackground(.hidden)
            .background(Color.pageBackground)
            .toolbarBackground(Color.pageBackground, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.coral)
    }

    func settingsCompactRowInsets() -> some View {
        self.listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }
}
