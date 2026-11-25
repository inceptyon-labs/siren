import API
import TVServices

/// Saves Continue Listening for the Top Shelf and asks the system to redraw it.
enum TVTopShelf {
  static func publish(_ books: [TVItem], progress: [String: Double]) {
    guard let server = Audiobookshelf.shared.authentication.server?.id else { return }
    let items = books.prefix(12).compactMap { book -> TopShelfSnapshot.Item? in
      guard let url = TVLinks.url(server: server, item: book.id) else { return nil }
      return TopShelfSnapshot.Item(
        id: book.id,
        title: book.title,
        imageURL: book.coverURL,
        progress: progress[book.id],
        playURL: url
      )
    }
    TopShelfSnapshot(items: items).save()
    TVTopShelfContentProvider.topShelfContentDidChange()
  }
}
