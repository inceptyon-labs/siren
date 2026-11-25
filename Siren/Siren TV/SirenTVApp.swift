import API
import SwiftUI

/// Siren on the Apple TV: Continue Listening and the library, a full-screen player, and the same
/// household profiles (Audiobookshelf sign-ins) as the phone. Streaming only.
@main
struct SirenTVApp: App {
  var body: some Scene {
    WindowGroup {
      TVRoot()
        .tint(SirenTheme.tint)
        .preferredColorScheme(.dark)
        .onOpenURL { url in Task { await TVLinks.open(url) } }
    }
  }
}

struct TVRoot: View {
  @State private var account = TVAccount.shared
  @State private var player = TVPlayer.shared

  var body: some View {
    Group {
      if account.serverID == nil, !Self.isDemo {
        TVSignIn()
      } else {
        TabView {
          TVHome().tabItem { Text("Home") }
          TVLibrary().tabItem { Text("Library") }
          TVProfiles().tabItem { Text("Profiles") }
        }
        .id(account.serverID)
      }
    }
    .background(SirenTheme.ground.ignoresSafeArea())
    .fullScreenCover(isPresented: $player.isShowing) { TVNowPlaying() }
    #if DEBUG
    .onAppear { TVDemo.start() }
    #endif
  }

  private static var isDemo: Bool {
    #if DEBUG
    TVDemo.screen != nil
    #else
    false
    #endif
  }
}

/// Which sign-in is active. Upstream's authentication service doesn't announce a switch, so the
/// TV's screens follow this instead, refreshed after signing in, switching or signing out.
@MainActor @Observable
final class TVAccount {
  static let shared = TVAccount()

  private(set) var serverID = Audiobookshelf.shared.authentication.server?.id

  func refresh() {
    serverID = Audiobookshelf.shared.authentication.server?.id
  }

  /// Makes `id` the active sign-in, with a book library chosen.
  func switchTo(_ id: String) async throws {
    await TVPlayer.shared.stop()
    try Audiobookshelf.shared.authentication.switchToServer(id)
    await TVLibraryChoice.ensure()
    refresh()
  }
}

/// Picks a book library when the signed-in server has none chosen (or a podcast one).
enum TVLibraryChoice {
  static func ensure() async {
    let libraries = Audiobookshelf.shared.libraries
    if let current = libraries.current, current.mediaType == .book { return }
    guard let all = try? await libraries.fetch() else { return }
    if let book = all.first(where: { $0.mediaType == .book }) { libraries.current = book }
  }
}

/// `siren://play?server=<id>&item=<id>` from the Top Shelf: switches to that sign-in if needed and
/// plays the book.
enum TVLinks {
  static func url(server: String, item: String) -> URL? {
    var components = URLComponents()
    components.scheme = "siren"
    components.host = "play"
    components.queryItems = [URLQueryItem(name: "server", value: server), URLQueryItem(name: "item", value: item)]
    return components.url
  }

  @MainActor static func open(_ url: URL) async {
    guard url.scheme == "siren", url.host == "play",
      let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
      let item = query.first(where: { $0.name == "item" })?.value
    else { return }
    if let server = query.first(where: { $0.name == "server" })?.value,
      Audiobookshelf.shared.authentication.server?.id != server
    {
      guard (try? await TVAccount.shared.switchTo(server)) != nil else { return }
    }
    await TVPlayer.shared.play(itemID: item)
  }
}
