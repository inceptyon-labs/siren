import Combine
import Foundation

final class LocalBookStorage: ObservableObject {
  static let shared = LocalBookStorage()

  private let booksKey = "local_books"

  @Published private(set) var books: [WatchBook]
  /// The saved list didn't decode, so the downloads on disk can't be matched to books.
  private(set) var couldNotRead = false

  private init() {
    guard let data = UserDefaults.standard.data(forKey: booksKey) else {
      self.books = []
      return
    }
    guard let books = try? JSONDecoder().decode([WatchBook].self, from: data) else {
      // SIREN: keep what couldn't be read instead of overwriting it with an empty list
      UserDefaults.standard.set(data, forKey: booksKey + ".unreadable")
      self.books = []
      couldNotRead = true
      return
    }
    self.books = books
  }

  func saveBooks(_ books: [WatchBook]) {
    // SIREN: the saved copy leaves out sign-in tokens; a download that then gets a 401 fetches
    // fresh track URLs from the phone
    let data = try? JSONEncoder().encode(books.map(\.withoutURLTokens))
    UserDefaults.standard.set(data, forKey: booksKey)
    self.books = books
  }

  func saveBook(_ book: WatchBook) {
    var updatedBooks = books
    if let index = updatedBooks.firstIndex(where: { $0.id == book.id }) {
      updatedBooks[index] = book
    } else {
      updatedBooks.append(book)
    }
    saveBooks(updatedBooks)
  }

  func updateBook(_ id: String, _ update: (inout WatchBook) -> Void) {
    var updatedBooks = books
    guard let index = updatedBooks.firstIndex(where: { $0.id == id }) else { return }
    update(&updatedBooks[index])
    saveBooks(updatedBooks)
  }

  func deleteBook(_ id: String) {
    var updatedBooks = books
    updatedBooks.removeAll { $0.id == id }
    saveBooks(updatedBooks)
  }

  func updateProgress(for bookID: String, currentTime: Double) {
    var updatedBooks = books
    if let index = updatedBooks.firstIndex(where: { $0.id == bookID }) {
      updatedBooks[index].currentTime = currentTime
      saveBooks(updatedBooks)
    }
  }
}

extension WatchBook {
  /// This book with any `token` query item taken out of its track URLs.
  fileprivate var withoutURLTokens: WatchBook {
    var copy = self
    copy.tracks = tracks.map { track in
      var track = track
      if let url = track.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
        components.queryItems?.contains(where: { $0.name == "token" }) == true
      {
        components.queryItems?.removeAll { $0.name == "token" }
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        track.url = components.url ?? url
      }
      return track
    }
    return copy
  }
}
