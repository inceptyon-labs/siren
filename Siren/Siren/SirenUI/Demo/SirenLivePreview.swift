import Foundation

/// Server-like shelves with real covers, for checking the live Home without a server.
extension HomePage.Model {
  static var sirenPreview: HomePage.Model {
    func book(
      _ title: String,
      _ author: String,
      isbn: String,
      progress: Double = 0,
      left: TimeInterval = 36_000,
      sequence: String? = nil
    ) -> BookCard.Model {
      BookCard.Model(
        id: isbn,
        title: title,
        cover: Cover.Model(url: URL(string: "https://covers.openlibrary.org/b/isbn/\(isbn)-L.jpg"), progress: progress),
        sequence: sequence,
        author: author,
        timeRemaining: left
      )
    }
    return HomePage.Model(sections: [
      Section(
        id: "continue-listening",
        title: "Continue Listening",
        items: .continueBooks(
          .init(items: [
            book("Dune", "Frank Herbert", isbn: "9780441013593", progress: 0.42, left: 41_000),
            book("The Martian", "Andy Weir", isbn: "9780553418026", progress: 0.15, left: 32_000),
            book("Mistborn", "Brandon Sanderson", isbn: "9780765311788", progress: 0.7, left: 22_000),
          ])
        )
      ),
      Section(
        id: "continue-series",
        title: "Continue Series",
        items: .books([
          book("Golden Son", "Pierce Brown", isbn: "9780345539816", sequence: "2"),
          book("The Well of Ascension", "Brandon Sanderson", isbn: "9780765316882", sequence: "2"),
          book("Caliban's War", "James S. A. Corey", isbn: "9780316129060", sequence: "2"),
        ])
      ),
      Section(
        id: "recently-added",
        title: "Recently Added",
        items: .books([
          book("Project Hail Mary", "Andy Weir", isbn: "9780593135204"),
          book("Children of Time", "Adrian Tchaikovsky", isbn: "9780316452502"),
          book("Recursion", "Blake Crouch", isbn: "9781524759780"),
          book("The Way of Kings", "Brandon Sanderson", isbn: "9780765326355"),
          book("Leviathan Wakes", "James S. A. Corey", isbn: "9780316129084"),
        ])
      ),
      Section(
        id: "listen-again",
        title: "Listen Again",
        items: .books([
          book("The Hobbit", "J. R. R. Tolkien", isbn: "9780547928227", progress: 1),
          book("The Name of the Wind", "Patrick Rothfuss", isbn: "9780756404741", progress: 1),
          book("Ready Player One", "Ernest Cline", isbn: "9780307887443", progress: 1),
        ])
      ),
      Section(
        id: "newest-authors",
        title: "Newest Authors",
        items: .authors([
          AuthorCard.Model(name: "Adrian Tchaikovsky"),
          AuthorCard.Model(name: "Blake Crouch"),
          AuthorCard.Model(name: "Pierce Brown"),
        ])
      ),
    ])
  }
}
