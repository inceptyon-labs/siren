import API
import SwiftUI

/// The app's main interface: Siren's tabs, mini player and player over upstream's services.
struct SirenLiveRoot: View {
  @StateObject private var playerManager = PlayerManager.shared
  @ObservedObject private var authentication = Audiobookshelf.shared.authentication
  @ObservedObject private var libraries = Audiobookshelf.shared.libraries
  @ObservedObject private var preferences = UserPreferences.shared
  @ObservedObject private var deepLinkManager = DeepLinkManager.shared
  @Environment(\.scenePhase) private var scenePhase

  @State private var router = SirenRouter.shared
  @State private var carMode = SirenCarMode.shared
  @State private var profiles = SirenProfiles.shared
  @State private var endOfBook = SirenEndOfBook.shared
  @State private var showingOnboarding = false
  @State private var showingServerList = false
  @State private var didCheckStartup = false
  @State private var isKeyboardVisible = false

  var body: some View {
    tabs
      // A profile switch rebuilds every screen on the new person's data.
      .id(profiles.activeID)
      .tint(SirenTheme.tint)
      .sheet(item: $endOfBook.card) { card in
        SirenEndOfBookSheet(card: card)
          .presentationDetents([.height(224)])
          .presentationDragIndicator(.visible)
      }
      .onChange(of: profiles.activeID) { _, _ in endOfBook.card = nil }
      .sheet(isPresented: playerBinding(assisted: false)) {
        if let current = playerManager.current {
          SirenLivePlayer(model: current) { router.openBook($0) }
            .presentationDragIndicator(.visible)
            .interactiveDismissDisabled(current.isLocked)
            .sirenPageSizing()
        }
      }
      .fullScreenCover(isPresented: playerBinding(assisted: true)) {
        if let current = playerManager.current {
          AssistedPlayer(model: current)
            .displayScaled()
            .interactiveDismissDisabled()
        }
      }
      .fullScreenCover(isPresented: $carMode.isPresented) {
        if let current = playerManager.current {
          SirenLiveCarMode(model: current)
        }
      }
      .fullScreenCover(item: $playerManager.reader) { reader in
        NavigationStack {
          EbookReaderView(model: reader)
        }
        .displayScaled()
      }
      .miniPlayerSheets(isEnabled: !playerManager.isShowingFullPlayer && !playerManager.isReaderOpen)
      .handleDeepLinks()
      .fullScreenCover(isPresented: $showingOnboarding) {
        OnboardingView(model: OnboardingViewModel())
          .displayScaled()
      }
      .sheet(isPresented: $showingServerList) {
        ServerListPage(model: ServerListModel())
          .displaySheetScaled()
      }
      .onAppear(perform: checkStartup)
      .task(id: profiles.activeID) { await SirenProfiles.ensureLibrary() }
      .onChange(of: libraries.current) { _, _ in
        showingServerList = false
        showingOnboarding = false
        router.homePath = NavigationPath()
        router.libraryPath = NavigationPath()
        router.searchPath = NavigationPath()
      }
      .onChange(of: deepLinkManager.isImportingConnection) { _, isImporting in
        if isImporting {
          showingOnboarding = false
          showingServerList = false
        }
      }
      .onChange(of: scenePhase) { _, phase in
        guard phase == .active else { return }
        if preferences.openPlayerOnLaunch || profiles.isKidsActive, playerManager.current != nil {
          playerManager.showFullPlayer()
        }
        carMode.checkRoute()
      }
      .onChange(of: playerManager.current?.id) { _, id in
        if id == nil {
          carMode.isPresented = false
        } else {
          carMode.checkRoute()
        }
      }
      .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
        isKeyboardVisible = true
      }
      .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
        isKeyboardVisible = false
      }
  }

  /// First launch goes to onboarding; a signed-out or library-less server opens the server list.
  private func checkStartup() {
    guard !didCheckStartup else { return }
    didCheckStartup = true
    if authentication.servers.isEmpty {
      showingOnboarding = true
    } else if !authentication.isAuthenticated || libraries.current == nil {
      showingServerList = true
    }
  }

  /// The kids profile always gets the assisted player.
  private var usesAssistedPlayer: Bool { preferences.assistedPlayer || profiles.isKidsActive }

  private func playerBinding(assisted: Bool) -> Binding<Bool> {
    Binding(
      get: {
        playerManager.isShowingFullPlayer && usesAssistedPlayer == assisted && !carMode.isPresented
      },
      set: { isShowing in
        if !isShowing { playerManager.hideFullPlayer() }
      }
    )
  }

  @ViewBuilder private var tabs: some View {
    if #available(iOS 26.0, *) {
      TabView(selection: $router.tab) {
        Tab("Home", systemImage: "house", value: SirenTab.home) { homeStack }
        Tab("Library", systemImage: "books.vertical", value: SirenTab.library) { libraryStack }
        Tab(value: SirenTab.search, role: .search) { searchStack }
      }
      .tabViewBottomAccessory {
        if let current = playerManager.current {
          SirenLiveMiniPlayer(model: current)
            .id(current.id)
        } else {
          Label("Pick a book to start listening", systemImage: "book")
            .font(.subheadline)
            .foregroundStyle(SirenTheme.secondary)
            .frame(maxWidth: .infinity)
        }
      }
    } else {
      TabView(selection: $router.tab) {
        homeStack
          .safeAreaInset(edge: .bottom) { legacyMiniPlayer }
          .tabItem { Label("Home", systemImage: "house") }
          .tag(SirenTab.home)
        libraryStack
          .safeAreaInset(edge: .bottom) { legacyMiniPlayer }
          .tabItem { Label("Library", systemImage: "books.vertical") }
          .tag(SirenTab.library)
        searchStack
          .safeAreaInset(edge: .bottom) { legacyMiniPlayer }
          .tabItem { Label("Search", systemImage: "magnifyingglass") }
          .tag(SirenTab.search)
      }
    }
  }

  @ViewBuilder private var legacyMiniPlayer: some View {
    if let current = playerManager.current, !isKeyboardVisible {
      SirenLiveMiniPlayer(model: current)
        .id(current.id)
        .padding(.vertical, 6)
        .background(.bar, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }
  }

  private var homeStack: some View {
    NavigationStack(path: $router.homePath) {
      SirenLiveHome()
        .sirenDestinations()
    }
  }

  private var libraryStack: some View {
    NavigationStack(path: $router.libraryPath) {
      // New models per library, as upstream's LibraryRootPage does.
      SirenLiveLibrary()
        .id(libraries.current?.id)
        .sirenDestinations()
    }
  }

  private var searchStack: some View {
    NavigationStack(path: $router.searchPath) {
      SirenLiveSearch()
        .id(libraries.current?.id)
        .sirenDestinations()
    }
  }
}
