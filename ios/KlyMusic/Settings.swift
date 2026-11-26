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
    @AppStorage("dolbyAtmosMode") private var dolbyAtmosMode = "auto"
    @AppStorage("crossfadeEnabled") private var crossfadeEnabled = false
    @AppStorage("crossfadeSeconds") private var crossfadeSeconds = 4.0
    @AppStorage("eqPreset") private var eqPreset = AudioEQPreset.off.rawValue
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
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            }
            .listRowBackground(Color.musicElevated)

            Section {
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
                    .frame(minHeight: 30)
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
                    .frame(minHeight: 30)
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
                        if eqPreset != AudioEQPreset.off.rawValue, let preset = AudioEQPreset(rawValue: eqPreset) {
                            SettingsValueText(text: L(preset.title))
                        } else if crossfadeEnabled {
                            SettingsValueText(text: String(format: L("%lld sn"), Int64(crossfadeSeconds.rounded())))
                        }
                    }
                    .frame(minHeight: 30)
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
                    .frame(minHeight: 30)
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
                    .frame(minHeight: 30)
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
                    .frame(minHeight: 30)
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
                    .frame(minHeight: 30)
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
                    .frame(minHeight: 30)
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
                    .frame(minHeight: 30)
                }
                .accessibilityIdentifier("settings.data")
                .settingsCompactRowInsets()

                NavigationLink {
                    aboutSettings
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "info.circle.fill", color: Color(red: 0.50, green: 0.52, blue: 0.58))
                        Text(L("Hakkında"))
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        SettingsValueText(text: "\(appVersion) (\(appBuild))")
                    }
                    .frame(minHeight: 30)
                }
                .accessibilityIdentifier("settings.about")
                .settingsCompactRowInsets()
            } header: {
                Text(L("Kütüphane ve Hakkında"))
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
        .musicSettingsList(sectionSpacing: 8)
        .environment(\.defaultMinListRowHeight, 36)
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
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.34, blue: 0.44), Color.coral, Color(red: 0.85, green: 0.16, blue: 0.34)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.20), lineWidth: 0.6)
                    }
                Image(systemName: "music.note")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)
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
    @EnvironmentObject private var player: MusicPlayer
    @AppStorage("crossfadeEnabled") private var crossfadeEnabled = false
    @AppStorage("crossfadeSeconds") private var crossfadeSeconds = 4.0
    @AppStorage("eqPreset") private var eqPreset = AudioEQPreset.off.rawValue
    @AppStorage("soundCheckEnabled") private var soundCheckEnabled = true
    @AppStorage("infiniteAutoplay") private var infiniteAutoplay = true
    @AppStorage("useListeningHistory") private var useListeningHistory = true
    @AppStorage("animatedArtwork") private var animatedArtwork = true

    private var activeEQTitle: String {
        L((AudioEQPreset(rawValue: eqPreset) ?? .off).title)
    }

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
                NavigationLink {
                    EqualizerSettingsView()
                } label: {
                    HStack(spacing: 12) {
                        SettingsIconTile(symbol: "slider.vertical.3", color: Color(red: 0.58, green: 0.34, blue: 0.88))
                        Text(L("Ekolayzer"))
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        SettingsValueText(text: activeEQTitle)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("settings.playback.eq")

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
        .onChange(of: soundCheckEnabled) { _, _ in player.applyAudioSettings() }
    }
}

private struct EqualizerSettingsView: View {
    @EnvironmentObject private var player: MusicPlayer
    @AppStorage("eqPreset") private var eqPreset = AudioEQPreset.off.rawValue

    private var currentPreset: AudioEQPreset { AudioEQPreset(rawValue: eqPreset) ?? .off }

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    eqBandMeter(label: "Bass", db: currentPreset.gainsDB.low)
                    eqBandMeter(label: "Mid", db: currentPreset.gainsDB.mid)
                    eqBandMeter(label: "Treble", db: currentPreset.gainsDB.high)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } header: {
                Text(L("Frekans Dengesi"))
            }
            .listRowBackground(Color.musicElevated)

            Section {
                ForEach(AudioEQPreset.allCases) { preset in
                    let selected = currentPreset == preset
                    Button {
                        eqPreset = preset.rawValue
                        player.applyAudioSettings()
                    } label: {
                        HStack {
                            Text(L(preset.title))
                                .font(.body)
                                .foregroundStyle(.primary)
                            Spacer(minLength: 12)
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.coral)
                                .frame(width: 22)
                                .opacity(selected ? 1 : 0)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(TrackRowButtonStyle())
                    .accessibilityIdentifier("settings.eq." + preset.rawValue)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .listRowBackground(Color.musicElevated)
        }
        .musicSettingsList()
        .navigationTitle(L("Ekolayzer"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func eqBandMeter(label: String, db: Float) -> some View {
        let normalized = CGFloat((db + 6.0) / 12.0)
        return VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 28, height: 52)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.coral)
                    .frame(width: 28, height: max(8, 52 * min(1, max(0.08, normalized))))
                    .animation(.spring(response: 0.28, dampingFraction: 0.78), value: db)
            }
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(String(format: "%+.1f dB", db))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SettingsIconTile: View {
    let symbol: String
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                }
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}

private struct SettingsDolbyTile: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(red: 0.16, green: 0.22, blue: 0.34))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                }
            DolbyDoubleDMark()
                .fill(.white, style: FillStyle(eoFill: true))
                .frame(width: 16, height: 10.8)
        }
        .frame(width: 28, height: 28)
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
        self.listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
    }
}
