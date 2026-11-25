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
    push(NavigationDestination.book(id: id))
  }

  /// Pushes onto the stack of the tab on screen.
  func push<Value: Hashable>(_ value: Value) {
    switch tab {
    case .home, .household: homePath.append(value)
    case .library: libraryPath.append(value)
    case .search: searchPath.append(value)
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
      case .author(let id, let name, let libraryID):
        SirenLiveAuthor(id: id, name: name, libraryID: libraryID)
      case .series, .narrator, .genre, .tag, .authorLibrary:
        SirenLiveBookList(destination: destination)
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
