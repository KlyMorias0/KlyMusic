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
        List {
            Group {
                settingsHeader("Dinleme")
                NavigationLink {
                    AudioQualitySettings(quality: $quality, lowData: $lowData)
                } label: {
                    settingValue("Ses kalitesi", value: L(lowData ? "Veri Tasarrufu" : "Yüksek Kalite"))
                }.accessibilityIdentifier("settings.quality")
                settingsHeader("İndirilenler")
                Toggle("Yalnızca Wi-Fi ile indir", isOn: $wifiOnly).tint(.green).frame(minHeight: 52).accessibilityIdentifier("settings.wifiOnly")
                NavigationLink { DownloadsView() } label: {
                    settingValue("İndirilen Müzikler", value: storageSize)
                }.accessibilityIdentifier("settings.downloads")
                settingsHeader("Görünüm")
                Picker("Görünüm", selection: $theme) {
                    Text("Sistem").tag("system"); Text("Açık").tag("light"); Text("Koyu").tag("dark")
                }.pickerStyle(.navigationLink).frame(minHeight: 52).accessibilityIdentifier("settings.theme")
                Picker("Dil", selection: $language) {
                    Text("Sistem").tag("system"); Text("Türkçe").tag("tr"); Text("English").tag("en")
                }.pickerStyle(.navigationLink).frame(minHeight: 52).accessibilityIdentifier("settings.language")
                settingsHeader("Kütüphane")
                NavigationLink { dataSettings } label: { Text("Kütüphane ve Veriler").frame(minHeight: 52) }.accessibilityIdentifier("settings.data")
                NavigationLink { aboutSettings } label: { Text("Hakkında").frame(minHeight: 52) }.accessibilityIdentifier("settings.about")
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
            } footer: { Text("Ses dosyaları yedeğe dahil edilmez.") }.listRowBackground(Color.pageBackground)
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

private struct AudioQualitySettings: View {
    @Binding var quality: String
    @Binding var lowData: Bool
    var body: some View {
        List {
            Section {
                option("Veri Tasarrufu", value: "data", subtitle: "Daha az internet kullanır.")
                option("Yüksek Kalite", value: "high", subtitle: "Kaynağın sunduğu yüksek kaliteli sesi kullanır.")
            } footer: {
                Text("Yeni tercih sonraki parçada uygulanır. İnternet kullanımı kaynağa ve bit hızına bağlıdır.")
            }.listRowBackground(Color.pageBackground)
        }.musicSettingsList()
            .navigationTitle("Ses kalitesi").navigationBarTitleDisplayMode(.inline)
    }
    private func option(_ title: String, value: String, subtitle: String) -> some View {
        let active = lowData == (value == "data")
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
