import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: MusicPlayer
    @AppStorage("quality") private var quality = "auto"
    @AppStorage("lowDataMode") private var lowData = true
    @AppStorage("wifiOnly") private var wifiOnly = true
    @AppStorage("theme") private var theme = "dark"
    @AppStorage("language") private var language = "system"
    @State private var status: String?
    @State private var document = BackupDocument()
    @State private var exporting = false
    @State private var importing = false
    @State private var eraseHistory = false
    private var selection: String { lowData ? "data" : "high" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 14) {
                    Image(systemName: "waveform").font(.system(size: 26, weight: .semibold))
                        .frame(width: 58, height: 58).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("KlyMusic").font(.system(size: 25, weight: .bold)).tracking(-0.5)
                        Text(L("Dinleme tercihlerin")).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(.top, 12)
                if let status {
                    Text(status).font(.footnote).padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityIdentifier("settings.status")
                }
                qualitySection
                appearanceSection
                offlineSection
                backupSection
                HStack {
                    NavigationLink {
                        ScrollView {
                            Text((Bundle.main.url(forResource: "ThirdPartyLicenses", withExtension: "txt")
                                  .flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? "")
                                .font(.footnote).textSelection(.enabled).padding(24)
                        }.navigationTitle("Lisanslar")
                    } label: { Text(L("Lisanslar")) }
                    Spacer()
                    Button(L("Geçmişi temizle"), role: .destructive) { eraseHistory = true }
                        .accessibilityIdentifier("settings.eraseHistory")
                }.font(.caption).foregroundStyle(.secondary)
                Text("KlyMusic \(version)").font(.caption2).foregroundStyle(.tertiary).frame(maxWidth: .infinity)
            }.padding(.horizontal, 24).padding(.bottom, 30).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background { AlbumBackdrop(artwork: (player.current ?? player.pendingTrack)?.artwork) }
        .navigationTitle("Ayarlar").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } } }
        .tint(.coral)
        .onChange(of: selection) { _, _ in player.refreshPreparation() }
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
            } catch { status = error.localizedDescription }
        }
        .confirmationDialog("Dinleme geçmişi temizlensin mi?", isPresented: $eraseHistory, titleVisibility: .visible) {
            Button("Geçmişi temizle", role: .destructive) { library.removeHistory() }
        }
    }

    private var qualitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Ses kalitesi")).font(.headline)
            HStack(spacing: 10) {
                qualityChoice("Az veri", value: "data", symbol: "leaf")
                qualityChoice("Yüksek", value: "high", symbol: "hifispeaker")
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(L(selection == "data" ? "Ses için yaklaşık 22–58 MB/saat" : selection == "high" ? "Ses için yaklaşık 58–115 MB/saat" : "Ses için yaklaşık 58 MB/saat"))
                    .font(.system(size: 13, weight: .medium))
                Text(L("Kaynağa göre değişir. Yeni tercih sonraki parçada uygulanır."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func qualityChoice(_ title: String, value: String, symbol: String) -> some View {
        let active = selection == value
        return Button {
            quality = value; lowData = value == "data"
        } label: {
            VStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 24, weight: .regular))
                Text(L(title)).font(.system(size: 13, weight: .semibold))
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14)).opacity(active ? 1 : 0.25)
            }.frame(maxWidth: .infinity).padding(.vertical, 18)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(active ? 0.45 : 0.05), lineWidth: active ? 1.5 : 0.5) }
                .foregroundStyle(active ? Color.primary : Color.secondary)
        }.buttonStyle(.plain).accessibilityIdentifier("settings.quality." + value)
            .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(L("Görünüm")).font(.headline)
            Picker("Tema", selection: $theme) {
                Text("Sistem").tag("system")
                Text("Açık").tag("light")
                Text("Koyu").tag("dark")
            }.pickerStyle(.segmented).accessibilityIdentifier("settings.theme")
            Menu {
                Picker("Dil", selection: $language) {
                    Text("Sistem").tag("system"); Text("Türkçe").tag("tr"); Text("English").tag("en")
                }
            } label: {
                HStack {
                    Image(systemName: "globe").foregroundStyle(.secondary)
                    Text(L("Dil"))
                    Spacer()
                    Text(language == "tr" ? "Türkçe" : language == "en" ? "English" : L("Sistem")).foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }.font(.subheadline).padding(.vertical, 7).foregroundStyle(.primary)
            }.accessibilityIdentifier("settings.language")
        }
    }

    private var offlineSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            NavigationLink { DownloadsView() } label: {
                HStack(spacing: 14) {
                    Image(systemName: "arrow.down.circle").font(.system(size: 31, weight: .light))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Çevrimdışı müzik")).font(.system(size: 17, weight: .semibold))
                        Text("\(library.downloaded.count) " + L("şarkı") + " · " + storageSize).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }.padding(20).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 23)).foregroundStyle(.primary)
            }.accessibilityIdentifier("settings.downloads")
            Toggle("Yalnızca Wi-Fi ile indir", isOn: $wifiOnly).font(.subheadline).accessibilityIdentifier("settings.wifiOnly")
        }
    }

    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Kütüphanen")).font(.headline)
            HStack(spacing: 12) {
                Button {
                    do { document = BackupDocument(data: try library.backup()); exporting = true }
                    catch { status = error.localizedDescription }
                } label: {
                    Label(L("Yedekle"), systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }.accessibilityIdentifier("settings.backup")
                Button { importing = true } label: {
                    Label(L("Geri yükle"), systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                }.accessibilityIdentifier("settings.restore")
            }.font(.system(size: 13, weight: .medium)).buttonStyle(.bordered).controlSize(.large).tint(.primary)
            Text(L("Favorilerini ve listelerini yanında tut. Ses dosyaları yedeğe dahil edilmez."))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    private var storageSize: String {
        let urls = (try? FileManager.default.contentsOfDirectory(at: MusicFiles.downloads, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let bytes = urls.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
