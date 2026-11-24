import SwiftUI

/// Tab and navigation state for the live Siren screens.
@MainActor @Observable
final class SirenRouter {
  static let shared = SirenRouter()

  var tab: SirenTab = .home
  var homePath = NavigationPath()
  var libraryPath = NavigationPath()
  var searchPath = NavigationPath()

  /// Pushes a book onto the current tab, closing the player first.
  func openBook(_ id: String) {
    PlayerManager.shared.hideFullPlayer()
    let destination = NavigationDestination.book(id: id)
    switch tab {
    case .home, .household: homePath.append(destination)
    case .library: libraryPath.append(destination)
    case .search: searchPath.append(destination)
    }
  }
}

extension View {
  /// Siren's screens for books; upstream's pages for everything Siren hasn't redrawn yet.
  func sirenDestinations() -> some View {
    navigationDestinations { destination in
      switch destination {
      case .book(let id):
        SirenLiveBookDetail(bookID: id)
      default:
        destination.resolvedView
      }
    }
    .navigationDestination(for: SirenRoute.self) { route in
      switch route {
      case .book(let id): SirenLiveBookDetail(bookID: id)
      case .progressArt: SirenProgressArtSettingsView()
      }
    }
  }
}
