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

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AudioQualitySettings(quality: $quality, lowData: $lowData)
                } label: {
                    HStack(spacing: 14) {
                        SettingsIconTile(symbol: "headphones", color: Color(red: 0.76, green: 0.38, blue: 0.54))
                        Text(L("Ses kalitesi"))
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 12)
                        SettingsValueText(text: currentQualityTitle)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("settings.quality")
                .accessibilityValue(currentQualityTitle)
            } header: {
                Text(L("Dinleme"))
            }
            .listRowBackground(Color.musicElevated)

            Section {
                Toggle(isOn: $wifiOnly) {
                    HStack(spacing: 14) {
                        SettingsIconTile(symbol: "wifi", color: Color(red: 0.20, green: 0.68, blue: 0.42))
                        Text(L("Yalnızca Wi-Fi ile indir"))
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    .frame(minHeight: 44)
                }
                .tint(Color.coral)
                .accessibilityIdentifier("settings.wifiOnly")

                NavigationLink {
                    DownloadsView()
                } label: {
                    HStack(spacing: 14) {
                        SettingsIconTile(symbol: "arrow.down.circle.fill", color: Color(red: 0.15, green: 0.50, blue: 0.95))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L("İndirilen Müzikler"))
                                .font(.body)
                                .foregroundStyle(.primary)
                            if !library.downloaded.isEmpty {
                                Text(String(format: L("%lld şarkı"), Int64(library.downloaded.count)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 12)
                        SettingsValueText(text: storageSize)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("settings.downloads")
                .accessibilityValue(storageSize)
            } header: {
                Text(L("İndirilenler"))
            }
            .listRowBackground(Color.musicElevated)

            Section {
                NavigationLink {
                    SettingsChoiceView(title: "Görünüm", selection: $theme, options: themeOptions, identifier: "settings.theme")
                } label: {
                    HStack(spacing: 14) {
                        SettingsIconTile(symbol: "moon.fill", color: Color(red: 0.38, green: 0.38, blue: 0.70))
                        Text(L("Görünüm"))
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 12)
                        SettingsValueText(text: currentThemeTitle)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("settings.theme")
                .accessibilityValue(currentThemeTitle)

                NavigationLink {
                    SettingsChoiceView(title: "Dil", selection: $language, options: languageOptions, identifier: "settings.language")
                } label: {
                    HStack(spacing: 14) {
                        SettingsIconTile(symbol: "globe", color: Color(red: 0.18, green: 0.65, blue: 0.72))
                        Text(L("Dil"))
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 12)
                        SettingsValueText(text: currentLanguageTitle)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("settings.language")
                .accessibilityValue(currentLanguageTitle)
            } header: {
                Text(L("Görünüm"))
            }
            .listRowBackground(Color.musicElevated)

            Section {
                NavigationLink {
                    dataSettings
                } label: {
                    HStack(spacing: 14) {
                        SettingsIconTile(symbol: "internaldrive.fill", color: Color(red: 0.95, green: 0.55, blue: 0.15))
                        Text(L("Kütüphane ve Veriler"))
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("settings.data")
            } header: {
                Text(L("Kütüphane"))
            }
            .listRowBackground(Color.musicElevated)

            Section {
                NavigationLink {
                    aboutSettings
                } label: {
                    HStack(spacing: 14) {
                        SettingsIconTile(symbol: "info.circle.fill", color: Color(red: 0.50, green: 0.52, blue: 0.58))
                        Text(L("Hakkında"))
                            .font(.body)
                            .foregroundStyle(.primary)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("settings.about")
            } header: {
                Text(L("Hakkında"))
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
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
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

private struct SettingsIconTile: View {
    let symbol: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(color)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                }
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 32, height: 32)
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

    var body: some View {
        List {
            Section {
                option("Otomatik", value: "auto", subtitle: "Ağın hızına göre en uygun kaliteyi seçer.")
                option("Veri Tasarrufu", value: "data", subtitle: "Daha az internet kullanır.")
                option("Yüksek kalite", value: "high", subtitle: "Kaynağın sunduğu yüksek kaliteli sesi kullanır.")
            } footer: {
                SettingsNote(text: "Yeni tercih sonraki parçada uygulanır. İnternet kullanımı kaynağa ve bit hızına bağlıdır.")
            }
            .listRowBackground(Color.musicElevated)
        }
        .musicSettingsList()
        .navigationTitle(L("Ses kalitesi"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func option(_ title: String, value: String, subtitle: String) -> some View {
        let active = (value == "auto" && !lowData && (quality == "auto" || quality.isEmpty)) ||
                     (value == "data" && lowData) ||
                     (value == "high" && !lowData && quality == "high")
        return Button {
            quality = value
            lowData = value == "data"
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
    func musicSettingsList() -> some View {
        self
            .listStyle(.insetGrouped)
            .listSectionSpacing(20)
            .scrollContentBackground(.hidden)
            .background(Color.pageBackground)
            .toolbarBackground(Color.pageBackground, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .tint(Color.coral)
    }
}
