import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore
    @AppStorage("quality") private var quality = "auto"
    @AppStorage("wifiOnly") private var wifiOnly = true
    @AppStorage("theme") private var theme = "dark"
    @AppStorage("language") private var language = "system"
    @State private var status: String?
    @State private var document = BackupDocument()
    @State private var exporting = false
    @State private var importing = false
    @State private var eraseHistory = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if let status {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "info.circle.fill").foregroundStyle(Color.musicAccent)
                        Text(status).font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 18)
                    .accessibilityIdentifier("settings.status")
                }
                listening
                appearance
                storage
                collection
                about
            }
            .padding(.horizontal, 22).padding(.top, 4).padding(.bottom, 32)
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(Color.musicBackground.ignoresSafeArea())
        .navigationTitle("Ayarlar").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.musicBackground, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Bitti") { dismiss() }.fontWeight(.semibold).foregroundStyle(.primary)
            }
        }
        .tint(Color.musicAccent)
        .presentationBackground(Color.musicBackground)
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

    private var listening: some View {
        settingsSection("Dinleme", topSpacing: 12) {
            Menu {
                Picker("Ses kalitesi", selection: $quality) {
                    Text("Otomatik").tag("auto")
                    Text("Yüksek kalite").tag("high")
                    Text("Veri tasarrufu").tag("data")
                }
            } label: {
                PreferenceRow(title: "Ses kalitesi", symbol: "waveform", value: qualityName)
            }
            .accessibilityLabel(L("Ses kalitesi")).accessibilityValue(qualityName)
            .accessibilityIdentifier("settings.quality")
            rowDivider
            Toggle(isOn: $wifiOnly) {
                PreferenceRow(title: "Yalnızca Wi-Fi ile indir", symbol: "wifi", showsChevron: false)
            }
            .tint(Color.musicAccent).accessibilityIdentifier("settings.wifiOnly")
        }
    }

    private var appearance: some View {
        settingsSection("Görünüm") {
            Menu {
                Picker("Tema", selection: $theme) {
                    Text("Sistem").tag("system")
                    Text("Açık").tag("light")
                    Text("Koyu").tag("dark")
                }
            } label: {
                PreferenceRow(title: "Tema", symbol: "circle.lefthalf.filled", value: themeName)
            }
            .accessibilityLabel(L("Tema")).accessibilityValue(themeName)
            .accessibilityIdentifier("settings.theme")
            rowDivider
            Menu {
                Picker("Dil", selection: $language) {
                    Text("Sistem").tag("system")
                    Text("Türkçe").tag("tr")
                    Text("English").tag("en")
                }
            } label: {
                PreferenceRow(title: "Dil", symbol: "globe", value: languageName)
            }
            .accessibilityLabel(L("Dil")).accessibilityValue(languageName)
            .accessibilityIdentifier("settings.language")
        }
    }

    private var collection: some View {
        settingsSection("Kütüphane") {
            Button {
                do { document = BackupDocument(data: try library.backup()); exporting = true }
                catch { status = error.localizedDescription }
            } label: {
                PreferenceRow(title: "Kütüphaneyi yedekle", symbol: "square.and.arrow.up")
            }.accessibilityIdentifier("settings.backup")
            rowDivider
            Button { importing = true } label: {
                PreferenceRow(title: "Yedeği geri yükle", symbol: "square.and.arrow.down")
            }.accessibilityIdentifier("settings.restore")
            rowDivider
            Button(role: .destructive) { eraseHistory = true } label: {
                PreferenceRow(title: "Dinleme geçmişini temizle", symbol: "clock.arrow.circlepath", destructive: true)
            }.accessibilityIdentifier("settings.eraseHistory")
            Text(L("Yedek; favorilerini, çalma listelerini ve ayarlarını içerir. İndirilen ses dosyaları yedeğe dahil edilmez."))
                .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).padding(.leading, 38).padding(.top, 10)
        }
    }

    private var storage: some View {
        settingsSection("Depolama") {
            NavigationLink { DownloadsView() } label: {
                PreferenceRow(title: "İndirilenleri yönet", symbol: "arrow.down.to.line", value: storageSize)
            }.accessibilityIdentifier("settings.downloads")
            Text("\(library.downloaded.count) şarkı")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.leading, 38).padding(.top, 2)
        }
    }

    private var about: some View {
        settingsSection("Uygulama") {
            NavigationLink {
                ScrollView {
                    Text((Bundle.main.url(forResource: "ThirdPartyLicenses", withExtension: "txt")
                          .flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? "")
                        .font(.footnote).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(24)
                }
                .background(Color.musicBackground).navigationTitle("Lisanslar")
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                PreferenceRow(title: "Açık kaynak lisansları", symbol: "doc.text")
            }
            HStack(spacing: 6) {
                Text("KlyMusic").fontWeight(.semibold)
                Text("\(version) · Beta")
            }
            .font(.caption).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).padding(.top, 30)
        }
    }

    private func settingsSection<Content: View>(_ title: String, topSpacing: CGFloat = 28, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L(title)).font(.headline).tracking(-0.3)
                .foregroundStyle(.primary).padding(.top, topSpacing).padding(.bottom, 8)
            content()
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Rectangle().fill(.primary.opacity(0.10)).frame(height: 0.5).padding(.leading, 38)
    }
    private var qualityName: String {
        L(quality == "high" ? "Yüksek kalite" : quality == "data" ? "Veri tasarrufu" : "Otomatik")
    }
    private var themeName: String { L(theme == "dark" ? "Koyu" : theme == "light" ? "Açık" : "Sistem") }
    private var languageName: String { language == "tr" ? "Türkçe" : language == "en" ? "English" : L("Sistem") }
    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }
    private var storageSize: String {
        let urls = (try? FileManager.default.contentsOfDirectory(at: MusicFiles.downloads, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let bytes = urls.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct PreferenceRow: View {
    var title: String
    var symbol: String
    var value: String? = nil
    var showsChevron = true
    var destructive = false
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 18, weight: .regular))
                .foregroundStyle(destructive ? Color.musicAccent : Color.primary.opacity(0.78))
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(L(title)).font(.subheadline)
                .foregroundStyle(destructive ? Color.musicAccent : Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let value {
                Text(value).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
            if showsChevron {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 56).contentShape(Rectangle())
    }
}
