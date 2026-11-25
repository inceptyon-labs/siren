import TVServices

/// Continue Listening on the Top Shelf: the covers the app last saved, each playing its book.
final class ContentProvider: TVTopShelfContentProvider {
  override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
    guard let snapshot = TopShelfSnapshot.load(), !snapshot.items.isEmpty else { return nil }
    let items = snapshot.items.map { entry in
      let item = TVTopShelfSectionedItem(identifier: entry.id)
      item.title = entry.title
      item.imageShape = .square
      if let progress = entry.progress, progress > 0 { item.playbackProgress = progress }
      if let url = entry.imageURL {
        item.setImageURL(url, for: .screenScale1x)
        item.setImageURL(url, for: .screenScale2x)
      }
      item.playAction = TVTopShelfAction(url: entry.playURL)
      item.displayAction = TVTopShelfAction(url: entry.playURL)
      return item
    }
    let section = TVTopShelfItemCollection(items: items)
    section.title = String(localized: "Continue Listening")
    return TVTopShelfSectionedContent(sections: [section])
  }
}
