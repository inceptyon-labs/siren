import API
import SirenKit
import SwiftUI

/// One place in a series: a book in the library, or one only Audible has (missing or upcoming).
enum SirenSeriesEntry: Identifiable {
  case owned(SirenBook)
  case audible(AudibleSeriesList.Book)

  var id: String {
    switch self {
    case .owned(let book): book.id
    case .audible(let book): "audible-\(book.id)"
    }
  }

  /// Merges the library's books in a series with Audible's list of it, in Audible's order. A
  /// library book matches an Audible one by ASIN, then title, then position; library books
  /// Audible doesn't list keep their own position.
  static func merge(owned: [(book: SirenBook, sequence: String?)], audible: AudibleSeriesList?) -> [Self] {
    guard let audible, !audible.books.isEmpty else {
      // Without Audible's list, the library's own positions.
      return owned.enumerated()
        .sorted {
          ($0.element.sequence.flatMap(Double.init) ?? .infinity, $0.offset)
            < ($1.element.sequence.flatMap(Double.init) ?? .infinity, $1.offset)
        }
        .map { .owned($0.element.book) }
    }
    var unmatched = owned
    var placed: [(entry: Self, position: Double)] = []
    for member in audible.books {
      let title = SirenText.matchKey(member.product.title)
      let match =
        unmatched.firstIndex { $0.book.asin == member.product.asin }
        ?? unmatched.firstIndex { SirenText.matchKey($0.book.title) == title }
        ?? unmatched.firstIndex { $0.sequence.flatMap(Double.init) == member.position }
      if let match {
        placed.append((.owned(unmatched.remove(at: match).book), member.position))
      } else {
        placed.append((.audible(member), member.position))
      }
    }
    for leftover in unmatched {
      placed.append((.owned(leftover.book), leftover.sequence.flatMap(Double.init) ?? .infinity))
    }
    // Stable: equal positions keep Audible's order.
    return placed.enumerated()
      .sorted { ($0.element.position, $0.offset) < ($1.element.position, $1.offset) }
      .map(\.element.entry)
  }
}

extension SirenText {
  /// Lowercased words without articles or punctuation, for matching titles across sources.
  static func matchKey(_ title: String) -> String {
    title.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { $0 != "the" && $0 != "a" }
      .joined(separator: " ")
  }
}

extension SirenRequests {
  /// Your live request for this book, if any. Failed and cancelled ones don't count: they can be
  /// made again.
  func liveRequest(asin: String) -> ReadMeABook.Request? {
    requests.first { $0.audiobook.audibleAsin == asin && !$0.status.canRequestAgain }
  }
}

extension AudibleSeriesList.Book {
  /// "Out Mar 4", or nil once it's out.
  var outLabel: String? {
    guard isUpcoming, let releaseDate else { return nil }
    return String(localized: "Out \(releaseDate.formatted(.dateTime.month(.abbreviated).day()))")
  }
}

/// Offers to request a book from Audible's catalog through ReadMeABook, or to connect it first.
struct SirenRequestDialog: ViewModifier {
  @Binding var product: AudibleProduct?
  /// Set for books not out yet; ReadMeABook holds those and fetches them on release day.
  var releaseDate: Date?
  var onConnect: () -> Void
  @State private var requests = SirenRequests.shared

  func body(content: Content) -> some View {
    content.confirmationDialog(
      product?.title ?? "",
      isPresented: Binding(get: { product != nil }, set: { if !$0 { product = nil } }),
      titleVisibility: .visible,
      presenting: product
    ) { product in
      if requests.liveRequest(asin: product.asin) != nil {
        // Nothing to do; the message says so.
      } else if requests.isConnected {
        Button(releaseDate == nil ? "Request" : "Request Now") { request(product) }
      } else {
        Button("Connect ReadMeABook", action: onConnect)
      }
    } message: { product in
      Text(message(product))
    }
  }

  private func message(_ product: AudibleProduct) -> String {
    var lines = [product.author]
    if let rating = product.rating {
      lines.append(
        String(
          localized:
            "Rated \(rating.average.formatted(.number.precision(.fractionLength(1)))) on Audible by \(rating.count.formatted()) listeners"
        )
      )
    }
    if let request = requests.liveRequest(asin: product.asin) {
      lines.append(request.status.label(progress: request.progress, releaseDate: request.releaseDate))
    } else if !requests.isConnected {
      lines.append(String(localized: "Connect ReadMeABook to request books you don't have."))
    } else if let releaseDate {
      lines.append(
        String(
          localized:
            "Out \(releaseDate.formatted(date: .long, time: .omitted)). ReadMeABook holds the request and gets it on release day."
        )
      )
    }
    return lines.filter { !$0.isEmpty }.joined(separator: "\n")
  }

  private func request(_ product: AudibleProduct) {
    Task {
      do {
        try await requests.request(product)
        Toast(success: "Requested \(product.title)").show()
      } catch let failure as ReadMeABook.Failure where failure.status == 409 {
        Toast(message: failure.localizedDescription).show()
        await requests.refresh()
      } catch {
        Toast(error: error.localizedDescription).show()
      }
    }
  }
}

extension View {
  func sirenRequestDialog(
    for product: Binding<AudibleProduct?>,
    releaseDate: Date? = nil,
    onConnect: @escaping () -> Void
  ) -> some View {
    modifier(SirenRequestDialog(product: product, releaseDate: releaseDate, onConnect: onConnect))
  }
}

extension SirenBook {
  /// A book only Audible has, drawn as a sketch.
  init(audible product: AudibleProduct) {
    self.init(id: product.asin, title: product.title, author: product.author, coverURL: product.coverURL)
    asin = product.asin
    apply(product.rating)
    inLibrary = false
  }
}

/// After you finish a book: the next one in its series, to play if you have it, or to request.
struct SirenNextInSeriesCard: View {
  let seriesName: String
  let next: SirenSeriesEntry
  /// Off in a kids profile.
  var canRequest = true
  /// After Play starts the next book.
  var onPlay: () -> Void = {}
  var onRequest: (AudibleSeriesList.Book) -> Void
  @State private var requests = SirenRequests.shared

  private var book: SirenBook {
    switch next {
    case .owned(let book): book
    case .audible(let member): SirenBook(audible: member.product)
    }
  }

  var body: some View {
    let book = book
    HStack(spacing: 12) {
      RevealCover(book: book, progress: book.inLibrary ? book.progress : 0, cornerRadius: 4, shadow: false)
        .frame(width: 56, height: 56)
      VStack(alignment: .leading, spacing: 2) {
        Text("Next in \(seriesName)")
          .font(.caption.weight(.semibold))
          .foregroundStyle(SirenTheme.secondary)
        Text(book.title)
          .font(SirenType.bookTitle(.headline))
          .foregroundStyle(SirenTheme.ink)
          .lineLimit(2)
        Text(detail)
          .font(.footnote)
          .foregroundStyle(SirenTheme.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      action
        .fixedSize()
    }
    .padding(12)
    .background(SirenTheme.raised, in: RoundedRectangle(cornerRadius: SirenTheme.rowRadius, style: .continuous))
  }

  private var detail: String {
    switch next {
    case .owned(let book):
      if book.isStarted { return String(localized: "\(Int((book.progress * 100).rounded()))% listened") }
      return String(localized: "In your library")
    case .audible(let member):
      if let request = requests.liveRequest(asin: member.product.asin) {
        return request.status.label(progress: request.progress, releaseDate: request.releaseDate)
      }
      return member.outLabel ?? String(localized: "Not in your library")
    }
  }

  @ViewBuilder private var action: some View {
    switch next {
    case .owned(let book):
      Button("Play") {
        onPlay()
        Task { await PlayerManager.shared.play(book.id) }
      }
      .buttonStyle(RequestSearchCapsuleStyle(filled: true))
      .accessibilityLabel("Play \(book.title)")
    case .audible(let member):
      if canRequest, requests.liveRequest(asin: member.product.asin) == nil {
        Button("Request") { onRequest(member) }
          .buttonStyle(RequestSearchCapsuleStyle(filled: !member.isUpcoming))
          .accessibilityLabel("Request \(member.product.title)")
      }
    }
  }
}

/// Works out a book's series from the server and Audible, for screens that don't load it already.
enum SirenSeriesResolver {
  /// The book's first series and every place in it, owned or not.
  @MainActor static func entries(bookID: String) async -> (name: String, entries: [SirenSeriesEntry])? {
    guard let book = try? await Audiobookshelf.shared.books.fetch(id: bookID),
      let series = book.series?.first
    else { return nil }
    let owned = await owned(seriesID: series.id, name: series.name, libraryID: book.libraryID)
    var audible: AudibleSeriesList?
    if let asin = book.media.metadata.asin, !asin.isEmpty {
      audible = await AudibleSeries.shared.series(ofBook: asin, named: series.name)
    }
    return (series.name, SirenSeriesEntry.merge(owned: owned, audible: audible))
  }

  /// The library's books in a series, with their positions in it.
  @MainActor static func owned(
    seriesID: String,
    name: String,
    libraryID: String?
  ) async -> [(book: SirenBook, sequence: String?)] {
    let filter = "series.\(Data(seriesID.utf8).base64EncodedString())"
    let members = (try? await Audiobookshelf.shared.books.fetch(filter: filter, libraryID: libraryID))?.results ?? []
    return members.map { member in
      (SirenBook(book: member), sequence(in: member.media.metadata.seriesName, of: name))
    }
  }

  /// A book's position in a series, from Audiobookshelf's "Name #1, Other #2". (Its filtered
  /// list carries the position elsewhere, in a field upstream's model doesn't read.)
  static func sequence(in seriesName: String?, of name: String) -> String? {
    guard let seriesName else { return nil }
    for part in seriesName.components(separatedBy: ", ") {
      guard part.hasPrefix("\(name) #") else { continue }
      let sequence = part.dropFirst(name.count + 2).trimmingCharacters(in: .whitespaces)
      return sequence.isEmpty ? nil : sequence
    }
    return nil
  }

  /// The next place after this book you haven't finished, owned or not.
  static func next(after bookID: String, in entries: [SirenSeriesEntry]) -> SirenSeriesEntry? {
    guard let index = entries.firstIndex(where: { $0.id == bookID }) else { return nil }
    return entries[(index + 1)...].first { entry in
      if case .owned(let book) = entry { return !book.isFinished }
      return true
    }
  }
}

/// When a book ends and nothing plays after it, the next book in its series: to play if you
/// have it, or to request. Upstream closes the player at that point, so this is its own sheet.
@MainActor @Observable
final class SirenEndOfBook {
  static let shared = SirenEndOfBook()

  struct Card: Identifiable {
    let finishedTitle: String
    let series: String
    let next: SirenSeriesEntry
    var id: String { next.id }
  }

  var card: Card?

  private init() {}

  /// Called by upstream's player when a book ends with nothing to continue to.
  func bookFinished(_ bookID: String) {
    let profile = SirenProfiles.shared.activeID
    Task {
      guard let found = await SirenSeriesResolver.entries(bookID: bookID),
        let next = SirenSeriesResolver.next(after: bookID, in: found.entries)
      else { return }
      let title = found.entries.compactMap { entry -> String? in
        if case .owned(let book) = entry, book.id == bookID { return book.title }
        return nil
      }.first
      // Let the player's sheet finish closing first.
      try? await Task.sleep(for: .milliseconds(600))
      // Someone else's book isn't theirs to play or request.
      guard SirenProfiles.shared.activeID == profile else { return }
      card = Card(finishedTitle: title ?? "", series: found.name, next: next)
    }
  }
}

/// The sheet `SirenEndOfBook` shows.
struct SirenEndOfBookSheet: View {
  let card: SirenEndOfBook.Card
  @Environment(\.dismiss) private var dismiss
  @State private var profiles = SirenProfiles.shared
  @State private var requesting: AudibleSeriesList.Book?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Finished")
          .font(.subheadline)
          .foregroundStyle(SirenTheme.secondary)
        Text(card.finishedTitle)
          .font(SirenType.bookTitle(.title2))
          .foregroundStyle(SirenTheme.ink)
          .lineLimit(2)
      }
      SirenNextInSeriesCard(
        seriesName: card.series,
        next: card.next,
        canRequest: !profiles.isKidsActive,
        onPlay: { dismiss() },
        onRequest: { requesting = $0 }
      )
    }
    .padding(20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .background(SirenTheme.ground)
    .sirenRequestDialog(
      for: Binding(get: { requesting?.product }, set: { if $0 == nil { requesting = nil } }),
      releaseDate: requesting?.isUpcoming == true ? requesting?.releaseDate : nil
    ) {
      dismiss()
      SirenRouter.shared.push(SirenRoute.requests)
    }
  }
}
