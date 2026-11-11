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
    private let themeOptions: [SettingsChoice] = [.init(title: "Sistem", value: "system"), .init(title: "Açık", value: "light"), .init(title: "Koyu", value: "dark")]
    private let languageOptions: [SettingsChoice] = [.init(title: "Sistem", value: "system"), .init(title: "Türkçe", value: "tr"), .init(title: "English", value: "en")]
    private var selection: String { lowData ? "data" : (quality == "high" ? "high" : "auto") }
    var body: some View {
        List {
            Group {
                settingsHeader("Dinleme")
                NavigationLink {
                    AudioQualitySettings(quality: $quality, lowData: $lowData)
                } label: {
                    settingValue("Ses kalitesi", value: L(lowData ? "Veri Tasarrufu" : (quality == "high" ? "Yüksek Kalite" : "Otomatik")))
                }.accessibilityIdentifier("settings.quality")
                settingsHeader("İndirilenler")
                Toggle("Yalnızca Wi-Fi ile indir", isOn: $wifiOnly).tint(.green).frame(minHeight: 52).accessibilityIdentifier("settings.wifiOnly")
                NavigationLink { DownloadsView() } label: {
                    settingValue("İndirilen Müzikler", value: storageSize)
                }.accessibilityIdentifier("settings.downloads")
                settingsHeader("Görünüm")
                NavigationLink {
                    SettingsChoiceView(title: "Görünüm", selection: $theme, options: themeOptions, identifier: "settings.theme")
                } label: { settingValue("Görünüm", value: L(themeOptions.first { $0.value == theme }?.title ?? "Sistem")) }
                    .accessibilityIdentifier("settings.theme")
                NavigationLink {
                    SettingsChoiceView(title: "Dil", selection: $language, options: languageOptions, identifier: "settings.language")
                } label: { settingValue("Dil", value: L(languageOptions.first { $0.value == language }?.title ?? "Sistem")) }
                    .accessibilityIdentifier("settings.language")
                settingsHeader("Kütüphane")
                NavigationLink { dataSettings } label: { Text(L("Kütüphane ve Veriler")).frame(minHeight: 52) }.accessibilityIdentifier("settings.data")
                NavigationLink { aboutSettings } label: { Text(L("Hakkında")).frame(minHeight: 52) }.accessibilityIdentifier("settings.about")
                if let status { Text(status).font(.footnote).accessibilityIdentifier("settings.status") }
            }.listRowBackground(Color.pageBackground)
                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
        }.musicSettingsList(compactHeaders: true)
            .navigationTitle("Ayarlar").navigationBarTitleDisplayMode(.inline).tint(.primary)
            .toolbarBackground(Color.pageBackground, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() }.foregroundStyle(.primary) } }
            .onChange(of: selection) { _, _ in player.refreshPreparation() }

    }
    private var dataSettings: some View {
        List {
            Section {
                Button {
                    do { document = BackupDocument(data: try library.backup()); exporting = true }
                    catch { status = error.localizedDescription }
                } label: { Text("Kütüphaneyi Yedekle") }.accessibilityIdentifier("settings.backup")
                Button("Yedeği Geri Yükle") { importing = true }.accessibilityIdentifier("settings.restore")
            } footer: { SettingsNote(text: "Ses dosyaları yedeğe dahil edilmez.") }
                .listRowBackground(Color.pageBackground).listSectionSeparator(.hidden, edges: .bottom)
            Section {
                Button("Dinleme Geçmişini Temizle", role: .destructive) { eraseHistory = true }
                    .accessibilityIdentifier("settings.eraseHistory")
            }.listRowBackground(Color.pageBackground)
            if let status { Section { Text(status).font(.footnote).accessibilityIdentifier("settings.status") } }
        }.musicSettingsList().navigationTitle("Kütüphane ve Veriler")
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "KlyMusic-Backup") { result in
                switch result {
                case .failure(let error): status = error.localizedDescription
                case .success: status = L("Kütüphane yedeklendi.")
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do {
                    let url = try result.get(); let allowed = url.startAccessingSecurityScopedResource()
                    defer { if allowed { url.stopAccessingSecurityScopedResource() } }
                    try library.restore(Data(contentsOf: url)); status = L("Kütüphane geri yüklendi.")
                } catch { status = error.localizedDescription }
            }
            .confirmationDialog("Dinleme geçmişi temizlensin mi?", isPresented: $eraseHistory, titleVisibility: .visible) {
                Button("Geçmişi temizle", role: .destructive) { library.removeHistory() }
            }
    }
    private var aboutSettings: some View {
        List {
            Section { settingValue("Uygulama", value: "KlyMusic"); settingValue("Sürüm", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") }.listRowBackground(Color.pageBackground)
            Section {
                NavigationLink("Lisanslar") {
                    ScrollView {
                        Text((Bundle.main.url(forResource: "ThirdPartyLicenses", withExtension: "txt").flatMap { try? String(contentsOf: $0) }) ?? "")
                            .font(.footnote).textSelection(.enabled).padding(20)
                    }.navigationTitle("Lisanslar")
                }
            }.listRowBackground(Color.pageBackground)
        }.musicSettingsList().navigationTitle("Hakkında")
    }
    private func settingsHeader(_ title: String) -> some View {
        Text(L(title)).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.top, 24).padding(.bottom, 8).listRowSeparator(.hidden)
    }
    private func settingValue(_ title: String, value: String) -> some View {
        HStack {
            Text(L(title)).foregroundStyle(.primary)
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }.frame(minHeight: 52)
    }
    private var storageSize: String {
        let urls = (try? FileManager.default.contentsOfDirectory(at: MusicFiles.downloads, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let bytes = urls.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return bytes == 0 ? L("Yok") : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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
        List(options, id: \.value) { option in
            Button { selection = option.value } label: {
                HStack {
                    Text(L(option.title)).foregroundStyle(.primary)
                    Spacer(minLength: 12)
                    if selection == option.value { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.primary) }
                }.frame(minHeight: 36).contentShape(Rectangle())
            }.listRowBackground(Color.pageBackground)
                .accessibilityIdentifier(identifier + "." + option.value)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
        }.musicSettingsList().navigationTitle(L(title)).navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsNote: View {
    let text: String
    var body: some View {
        Text(L(text)).font(.footnote).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
            .listRowSeparator(.hidden)
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
                option("Yüksek Kalite", value: "high", subtitle: "Kaynağın sunduğu yüksek kaliteli sesi kullanır.")
            } footer: {
                SettingsNote(text: "Yeni tercih sonraki parçada uygulanır. İnternet kullanımı kaynağa ve bit hızına bağlıdır.")
            }.listRowBackground(Color.pageBackground).listSectionSeparator(.hidden, edges: .bottom)
        }.musicSettingsList()
            .navigationTitle(L("Ses kalitesi")).navigationBarTitleDisplayMode(.inline)
    }
    private func option(_ title: String, value: String, subtitle: String) -> some View {
        let active = (value == "auto" && !lowData && (quality == "auto" || quality.isEmpty)) || (value == "data" && lowData) || (value == "high" && !lowData && quality == "high")
        return Button { quality = value; lowData = value == "data" } label: {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L(title)).foregroundStyle(.primary)
                    Text(L(subtitle)).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if active { Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.primary) }
            }.padding(.vertical, 4)
        }.accessibilityIdentifier("settings.quality." + value).accessibilityAddTraits(active ? .isSelected : [])
    }
}

private extension View {
    func musicSettingsList(compactHeaders: Bool = false) -> some View {
        self.listStyle(.plain).scrollContentBackground(.hidden).background(Color.pageBackground)
            .environment(\.defaultMinListRowHeight, compactHeaders ? 0 : 54)
            .contentMargins(.top, 8, for: .scrollContent)
    }
}
