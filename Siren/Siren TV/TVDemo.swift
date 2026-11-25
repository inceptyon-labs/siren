#if DEBUG
import Foundation

/// Launch with `-SirenTVDemo home` (or `player`) to see the screens without a server: made-up
/// books on plain plates, for checking layout.
enum TVDemo {
  static var screen: String? {
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: "-SirenTVDemo"), arguments.indices.contains(index + 1) else {
      return nil
    }
    return arguments[index + 1]
  }

  private static let titles = [
    "The Salt Road", "The Glass Orchard", "Harbor of Bells", "A Map of Small Hours", "The Long Quiet",
    "North of Everything", "The Beekeeper's Year", "Copper Sky", "The House on Wren Lane", "Small Gods of Winter",
    "A Field Guide to Leaving", "The Ferryman's Daughter", "Orchard Weather", "Iron and Orchid",
  ]

  static var shelves: [TVHome.Shelf]? {
    guard screen != nil else { return nil }
    let items = titles.enumerated().map { TVItem(id: "demo-\($0.offset)", title: $0.element, coverURL: nil) }
    return [
      TVHome.Shelf(id: "continue-listening", title: "Continue Listening", books: Array(items.prefix(4))),
      TVHome.Shelf(id: "recently-added", title: "Recently Added", books: Array(items.dropFirst(4))),
      TVHome.Shelf(id: "listen-again", title: "Listen Again", books: Array(items.suffix(5))),
    ]
  }

  static let progress = ["demo-0": 0.57, "demo-1": 0.12, "demo-2": 0.81, "demo-3": 0.3, "demo-9": 1.0]

  @MainActor static func start() {
    guard screen == "player" else { return }
    let chapters = (0..<24).map {
      TVPlayer.Chapter(id: $0, start: Double($0) * 1500, end: Double($0 + 1) * 1500, title: "Chapter \($0 + 1)")
    }
    TVPlayer.shared.showDemo(
      TVPlayer.Book(
        itemID: "demo-0",
        serverID: "demo",
        title: "The Salt Road",
        author: "Mara Kessling",
        coverURL: nil,
        duration: 36_000,
        chapters: chapters
      ),
      at: 20_640
    )
    TVPlayer.shared.isShowing = true
  }
}
#endif
