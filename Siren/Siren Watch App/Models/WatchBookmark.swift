import Foundation

struct WatchBookmark: Codable, Identifiable {
  var id: Int { time }

  let time: Int
  let title: String

  init(time: Int, title: String) {
    self.time = time
    self.title = title
  }

  init?(dictionary: [String: Any]) {
    guard let time = dictionary["time"] as? Int, let title = dictionary["title"] as? String else { return nil }

    self.init(time: time, title: title)
  }
}

final class WatchBookmarkStore {
  static let shared = WatchBookmarkStore()

  private let bookmarksKey = "bookmarks"

  private var bookmarksByBook: [String: [WatchBookmark]]
  /// When each bookmark was added here, so one the phone hasn't saved yet survives a merge.
  private var addedAt: [String: Date] = [:]  // SIREN

  private init() {
    guard let data = UserDefaults.standard.data(forKey: bookmarksKey) else {
      self.bookmarksByBook = [:]
      return
    }
    guard let bookmarksByBook = try? JSONDecoder().decode([String: [WatchBookmark]].self, from: data) else {
      // SIREN: keep bookmarks that couldn't be read instead of overwriting them
      UserDefaults.standard.set(data, forKey: bookmarksKey + ".unreadable")
      self.bookmarksByBook = [:]
      return
    }
    self.bookmarksByBook = bookmarksByBook
  }

  func bookmarks(for bookID: String) -> [WatchBookmark] {
    bookmarksByBook[bookID] ?? []
  }

  func add(_ bookmark: WatchBookmark, for bookID: String) {
    addedAt["\(bookID)|\(bookmark.time)"] = .now
    save(bookmarks(for: bookID) + [bookmark], for: bookID)
  }

  func merge(_ synced: [WatchBookmark], keeping inFlightTimes: Set<Int>, for bookID: String) {
    let syncedTimes = Set(synced.map(\.time))
    // SIREN: a transfer can be delivered before the phone has saved the bookmark, so keep
    // anything added in the last two minutes too
    let unconfirmed = bookmarks(for: bookID).filter { bookmark in
      guard !syncedTimes.contains(bookmark.time) else { return false }
      let recent = addedAt["\(bookID)|\(bookmark.time)"].map { Date.now.timeIntervalSince($0) < 120 } ?? false
      return inFlightTimes.contains(bookmark.time) || recent
    }
    for time in syncedTimes { addedAt["\(bookID)|\(time)"] = nil }
    save(synced + unconfirmed, for: bookID)
  }

  private func save(_ bookmarks: [WatchBookmark], for bookID: String) {
    bookmarksByBook[bookID] = bookmarks.sorted { $0.time < $1.time }
    guard let data = try? JSONEncoder().encode(bookmarksByBook) else { return }
    UserDefaults.standard.set(data, forKey: bookmarksKey)
  }
}
