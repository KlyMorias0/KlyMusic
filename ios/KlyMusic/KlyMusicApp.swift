import SwiftUI
import SwiftData

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
        UserDefaults.standard.register(defaults: ["wifiOnly": true, "quality": "auto", "theme": "dark", "language": "system"])
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
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { listeningLocale = ListeningLocale.current }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in
                    listeningLocale = ListeningLocale.current
                }
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
                    TabShell { HomeView() }
                }.accessibilityIdentifier("nav.home")
                Tab(L("Keşfet"), systemImage: "square.grid.2x2.fill", value: 1) {
                    TabShell { DiscoverView() }
                }.accessibilityIdentifier("nav.discover")
                Tab(L("Kütüphane"), systemImage: "square.stack.fill", value: 2) {
                    TabShell { LibraryView() }
                }.accessibilityIdentifier("nav.library")
                Tab(L("Ara"), systemImage: "magnifyingglass", value: 3, role: .search) {
                    TabShell { SearchView() }
                }.accessibilityIdentifier("nav.search")
            }
        } else {
            TabView(selection: $tab) {
                TabShell { HomeView() }
                    .tabItem { Label(L("Dinle"), systemImage: "house.fill").accessibilityIdentifier("nav.home") }
                    .tag(0)
                TabShell { DiscoverView() }
                    .tabItem { Label(L("Keşfet"), systemImage: "square.grid.2x2.fill").accessibilityIdentifier("nav.discover") }
                    .tag(1)
                TabShell { LibraryView() }
                    .tabItem { Label(L("Kütüphane"), systemImage: "square.stack.fill").accessibilityIdentifier("nav.library") }
                    .tag(2)
                TabShell { SearchView() }
                    .tabItem { Label(L("Ara"), systemImage: "magnifyingglass").accessibilityIdentifier("nav.search") }
                    .tag(3)
            }
        }
    }
}

struct TabShell<Content: View>: View {
    @EnvironmentObject private var player: MusicPlayer
    @ViewBuilder var content: () -> Content
    var body: some View {
        NavigationStack {
            content()
                .background(Color.musicBackground)
                .toolbarBackground(Color.musicBackground.opacity(0.96), for: .navigationBar)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if #available(iOS 26.0, *) {
                        EmptyView()
                    } else if player.current != nil || player.pendingTrack != nil {
                        MiniPlayer().padding(.horizontal, 12).padding(.vertical, 6)
                    }
                }
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
