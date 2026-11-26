import SwiftUI
import SwiftData
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        DownloadManager.shared.backgroundCompletion = completionHandler
        DownloadManager.shared.reconnect()
    }
}

@main struct KlyMusicApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    private let container: ModelContainer
    private let startupError: String?
    @StateObject private var library: LibraryStore
    @StateObject private var player = MusicPlayer()
    @StateObject private var downloads = DownloadManager.shared
    @AppStorage("theme") private var theme = "dark"
    @AppStorage("language") private var language = "system"
    @Environment(\.scenePhase) private var scenePhase
    @State private var listeningLocale = ListeningLocale.current
    @State private var wasInBackground = false

    init() {
        do {
            let container = try ModelContainer(for: SavedTrack.self, SavedPlaylist.self)
            self.container = container
            startupError = nil
            let store = LibraryStore(context: ModelContext(container))
            _library = StateObject(wrappedValue: store)
            DownloadManager.shared.library = store
        } catch {
            startupError = error.localizedDescription
            let temporary = try! ModelContainer(for: SavedTrack.self, SavedPlaylist.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            container = temporary
            let store = LibraryStore(context: ModelContext(temporary))
            _library = StateObject(wrappedValue: store)
            DownloadManager.shared.library = store
        }
        UserDefaults.standard.register(defaults: [
            "wifiOnly": true,
            "quality": "auto",
            "theme": "dark",
            "language": "system",
            "infiniteAutoplay": true,
            "useListeningHistory": true,
            "soundCheckEnabled": true,
            "animatedArtwork": true,
            "dolbyAtmosMode": "auto",
            "crossfadeEnabled": false,
            "crossfadeSeconds": 4.0,
            "losslessEnabled": true,
            "autoDownloadFavorites": false,
            "eqPreset": "off"
        ])
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let startupError {
                    EmptyState(symbol: "externaldrive.badge.exclamationmark", title: L("Kütüphane açılamadı"), message: L("Verilerin silinmedi. Boş alanı kontrol edip uygulamayı yeniden aç.") + "\n" + startupError)
                } else { RootView() }
            }
                .id(language + "|" + listeningLocale.cacheKey)
                .environmentObject(library).environmentObject(player).environmentObject(downloads)
                .environmentObject(player.clock)
                .modelContainer(container)
                .tint(.coral)
                .preferredColorScheme(theme == "dark" ? .dark : theme == "light" ? .light : nil)
                .environment(\.locale, Locale(identifier: AppLanguage.current))
                .task {
                    player.library = library; downloads.library = library; downloads.reconnect()
                    player.restoreLastSessionIfNeeded()
                    player.applyAudioSettings()
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        wasInBackground = true
                    } else if phase == .active {
                        listeningLocale = ListeningLocale.current
                        if wasInBackground {
                            wasInBackground = false
                            if player.current != nil && !player.isPresented {
                                player.isPresented = true
                            }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                    listeningLocale = ListeningLocale.current
                }
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "klymusic",
              url.host?.lowercased() == "player" else { return }
        if player.library == nil { player.library = library }
        let action = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        switch action {
        case "open", "":
            if player.current != nil || player.pendingTrack != nil {
                player.isPresented = true
            }
        case "toggle":
            player.toggle()
        case "next":
            player.next()
        case "previous":
            player.previous()
        case "favorite":
            if let track = player.current ?? player.pendingTrack {
                library.toggleFavorite(track)
            }
        default:
            break
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var player: MusicPlayer
    @EnvironmentObject private var library: LibraryStore
    @State private var tab = 0
    var body: some View {
        tabs
        .modifier(NativePlayerAccessory(isVisible: player.current != nil || player.pendingTrack != nil))
        .sheet(isPresented: $player.isPresented) {
            NavigationStack { NowPlayingView().toolbar(.hidden, for: .navigationBar) }
                .presentationDragIndicator(.hidden).presentationCornerRadius(30)
                .presentationDetents([.large])
        }
        .alert("Oynatma", isPresented: Binding(get: { player.error != nil }, set: { if !$0 { player.error = nil } })) {
            Button("Tamam", role: .cancel) { player.error = nil }
        } message: { Text(player.error ?? "") }
        .alert("Kütüphane", isPresented: Binding(get: { library.error != nil }, set: { if !$0 { library.error = nil } })) {
            Button("Tamam", role: .cancel) { library.error = nil }
        } message: { Text(library.error ?? "") }
    }

    @ViewBuilder private var tabs: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $tab) {
                Tab(L("Dinle"), systemImage: "house.fill", value: 0) {
                    TabShell(isSelected: tab == 0) { HomeView() }
                }.accessibilityIdentifier("nav.home")
                Tab(L("Keşfet"), systemImage: "square.grid.2x2.fill", value: 1) {
                    TabShell(isSelected: tab == 1) { DiscoverView() }
                }.accessibilityIdentifier("nav.discover")
                Tab(L("Radyo"), systemImage: "dot.radiowaves.left.and.right", value: 2) {
                    TabShell(isSelected: tab == 2) { RadioView() }
                }.accessibilityIdentifier("nav.radio")
                Tab(L("Kütüphane"), systemImage: Self.libraryTabSymbol, value: 3) {
                    TabShell(isSelected: tab == 3) { LibraryView() }
                }.accessibilityIdentifier("nav.library")
                Tab(L("Ara"), systemImage: "magnifyingglass", value: 4, role: .search) {
                    TabShell(isSelected: tab == 4) { SearchView() }
                }.accessibilityIdentifier("nav.search")
            }
        } else {
            TabView(selection: $tab) {
                TabShell(isSelected: tab == 0) { HomeView() }
                    .tabItem { Label(L("Dinle"), systemImage: "house.fill").accessibilityIdentifier("nav.home") }
                    .tag(0)
                TabShell(isSelected: tab == 1) { DiscoverView() }
                    .tabItem { Label(L("Keşfet"), systemImage: "square.grid.2x2.fill").accessibilityIdentifier("nav.discover") }
                    .tag(1)
                TabShell(isSelected: tab == 2) { RadioView() }
                    .tabItem { Label(L("Radyo"), systemImage: "dot.radiowaves.left.and.right").accessibilityIdentifier("nav.radio") }
                    .tag(2)
                TabShell(isSelected: tab == 3) { LibraryView() }
                    .tabItem { Label(L("Kütüphane"), systemImage: Self.libraryTabSymbol).accessibilityIdentifier("nav.library") }
                    .tag(3)
                TabShell(isSelected: tab == 4) { SearchView() }
                    .tabItem { Label(L("Ara"), systemImage: "magnifyingglass").accessibilityIdentifier("nav.search") }
                    .tag(4)
            }
        }
    }

    static let libraryTabSymbol: String = {
        for name in ["music.note.square.stack.fill", "play.square.stack.fill", "square.stack.fill"] {
            if UIImage(systemName: name) != nil { return name }
        }
        return "square.stack.fill"
    }()
}

struct TabShell<Content: View>: View {
    var isSelected: Bool = false
    @EnvironmentObject private var player: MusicPlayer
    @State private var pushedTarget: AppNavigationTarget?
    @ViewBuilder var content: () -> Content
    var body: some View {
        NavigationStack {
            content()
                .background(Color.musicBackground)
                .toolbarBackground(Color.musicBackground.opacity(0.96), for: .navigationBar)
                .navigationDestination(item: $pushedTarget) { target in
                    switch target {
                    case .artist(let id, let name):
                        ArtistDetailView(id: id, name: name)
                    case .album(let collection):
                        AlbumDetailView(collection: collection)
                    case .query(let title, let query):
                        QueryView(query: query, title: title)
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if #available(iOS 26.0, *) {
                        EmptyView()
                    } else if player.current != nil || player.pendingTrack != nil {
                        MiniPlayer().padding(.horizontal, 12).padding(.vertical, 6)
                    }
                }
        }
        .onChange(of: player.requestedNavigation) { _, target in
            guard isSelected, let target else { return }
            pushedTarget = target
            player.requestedNavigation = nil
        }
    }
}

/// Let the system own the tab bar and its glass player container on iOS 26.
private struct NativePlayerAccessory: ViewModifier {
    var isVisible: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.1, *) {
            content
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory(isEnabled: isVisible) {
                    NativeMiniPlayer()
                }
        } else if #available(iOS 26.0, *) {
            content
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory {
                    if isVisible { NativeMiniPlayer() }
                }
        } else {
            content
        }
    }
}

@available(iOS 26.0, *)
private struct NativeMiniPlayer: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        MiniPlayer(inSystemAccessory: true, isCompact: placement == .inline)
    }
}
