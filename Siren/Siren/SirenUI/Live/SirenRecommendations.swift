import API
import Models
import SirenKit
import SwiftUI

/// Home's recommendations, worked out on the device from Audible's catalog, so they cost nothing:
/// - Because you liked: books Audible lists as similar to the ones you liked or finished, ranked
///   by how many of those point at the same book × its rating × log(how many rated it), leaving
///   out what's already in the library or requested.
/// - Highly rated in your library: books you have but haven't started, rated 4.5 or more.
@MainActor @Observable
final class SirenRecommendations {
  static let shared = SirenRecommendations()

  /// The liked or finished book the shelf is named after, and Audible's picks for it.
  private(set) var seedTitle: String?
  private(set) var picks: [AudibleProduct] = []
  private(set) var unstarted: [SirenBook] = []

  private struct Key: Equatable {
    let serverID: String?
    let libraryID: String?
  }

  @ObservationIgnored private var loadedKey: Key?
  /// Whose library the shelves on screen came from.
  @ObservationIgnored private var shownKey: Key?
  @ObservationIgnored private var loadedAt: Date?
  @ObservationIgnored private var running: Task<Void, Never>?

  /// Seeds asked about: Audible gets one request per seed, so this bounds a first load.
  private static let seedLimit = 10
  private static let shelfSize = 12

  private init() {}

  private static var currentKey: Key {
    Key(
      serverID: Audiobookshelf.shared.authentication.server?.id,
      libraryID: Audiobookshelf.shared.libraries.current?.id
    )
  }

  /// Works them out again when the profile or library changed, an hour has passed, or `force`.
  func refresh(force: Bool = false) async {
    // Another profile's books go at once, before waiting on anything.
    clearIfStale()
    if let running { await running.value }
    clearIfStale()
    let key = Self.currentKey
    if key == loadedKey, !force, let loadedAt, Date().timeIntervalSince(loadedAt) < 3600 {
      return
    }
    // Another caller started one while this waited.
    if let running {
      await running.value
      return
    }
    let task = Task {
      await self.load(key)
      self.running = nil
    }
    running = task
    await task.value
  }

  private func clearIfStale() {
    guard let shownKey, shownKey != Self.currentKey else { return }
    self.shownKey = nil
    // Coming back to this library has to load it again.
    loadedKey = nil
    loadedAt = nil
    seedTitle = nil
    picks = []
    unstarted = []
  }

  private func load(_ key: Key) async {
    guard let libraryID = key.libraryID,
      let library = try? await Audiobookshelf.shared.books.fetch(libraryID: libraryID).results,
      Self.currentKey == key
    else { return }

    // From the server, not the local store: Home may not have synced it yet.
    guard let progress = try? await Self.progress() else { return }
    let liked = (try? await Likes.playlist())?.items.map(\.libraryItemID) ?? []
    guard Self.currentKey == key else { return }

    await loadPicks(library: library, progress: progress, liked: liked, key: key)
    await loadUnstarted(library: library, progress: progress, key: key)
    guard Self.currentKey == key else { return }
    loadedKey = key
    loadedAt = Date()
  }

  nonisolated private struct Me: Decodable, Sendable {
    let mediaProgress: [User.MediaProgress]
  }

  /// Your progress on every book (`GET /api/me`); podcast episodes left out.
  private static func progress() async throws -> [User.MediaProgress] {
    let me: Me = try await Audiobookshelf.shared.send("/api/me")
    return me.mediaProgress.filter { $0.episodeId == nil }
  }

  // MARK: Because you liked

  private func loadPicks(library: [Book], progress: [User.MediaProgress], liked: [String], key: Key) async {
    let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    // Likes first, newest first, then finished books, most recently finished first.
    let finished = progress.filter(\.isFinished)
      .sorted { ($0.finishedAt ?? $0.lastUpdate) > ($1.finishedAt ?? $1.lastUpdate) }
      .map(\.libraryItemId)
    var seen = Set<String>()
    let seeds = (liked.reversed() + finished)
      .filter { seen.insert($0).inserted }
      .compactMap { byID[$0] }
      .filter { $0.media.metadata.asin?.isEmpty == false }
      .prefix(Self.seedLimit)

    var similar: [(seed: Book, products: [AudibleProduct])] = []
    for seed in seeds {
      guard let asin = seed.media.metadata.asin,
        let products = await AudibleSimilar.shared.products(like: asin)
      else { continue }
      guard Self.currentKey == key else { return }
      similar.append((seed, products))
    }

    let ownedASINs = Set(library.compactMap(\.media.metadata.asin))
    let ownedTitles = Set(library.map { Self.normalized($0.title) })
    // Failed and cancelled requests can be made again, so those books stay in.
    let requested = Set(
      SirenRequests.shared.requests.filter { !$0.status.canRequestAgain }.compactMap(\.audiobook.audibleAsin)
    )
    func isNew(_ product: AudibleProduct) -> Bool {
      !ownedASINs.contains(product.asin) && !requested.contains(product.asin)
        && !ownedTitles.contains(Self.normalized(product.title))
    }

    // How many seeds point at each book.
    var votes: [String: Int] = [:]
    for entry in similar {
      for asin in Set(entry.products.map(\.asin)) { votes[asin, default: 0] += 1 }
    }
    func score(_ product: AudibleProduct) -> Double {
      guard let rating = product.rating, rating.count > 1 else { return 0 }
      return Double(votes[product.asin] ?? 1) * rating.average * log(Double(rating.count))
    }

    // The newest seed with enough new books to fill a shelf names it.
    for entry in similar {
      let ranked = entry.products.filter(isNew)
        .map { ($0, score($0)) }
        .filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
      if ranked.count >= 3 {
        seedTitle = entry.seed.title
        picks = Array(ranked.prefix(Self.shelfSize))
        shownKey = key
        return
      }
    }
    seedTitle = nil
    picks = []
    shownKey = key
  }

  /// Lowercased letters and digits only, so "The Way of Kings" matches "Way of Kings, The".
  private static func normalized(_ title: String) -> String {
    let words = title.lowercased().split { !$0.isLetter && !$0.isNumber }.filter { $0 != "the" && $0 != "a" }
    return words.joined(separator: " ")
  }

  // MARK: Highly rated in your library

  private func loadUnstarted(library: [Book], progress: [User.MediaProgress], key: Key) async {
    let touched = Set(progress.filter { $0.isFinished || $0.progress > 0 }.map(\.libraryItemId))
    let candidates = library.filter { !touched.contains($0.id) && $0.media.metadata.asin?.isEmpty == false }
    await AudibleRatings.shared.load(candidates.compactMap(\.media.metadata.asin))
    guard Self.currentKey == key else { return }
    let rated: [(book: SirenBook, score: Double)] = candidates.compactMap { item in
      guard let rating = AudibleRatings.shared.rating(for: item.media.metadata.asin),
        (rating.average * 10).rounded() / 10 >= 4.5, rating.count > 1
      else { return nil }
      var book = SirenBook(book: item)
      book.apply(rating)
      return (book, rating.average * log(Double(rating.count)))
    }
    shownKey = key
    unstarted = rated.sorted { $0.score > $1.score }.prefix(Self.shelfSize).map(\.book)
  }
}

/// Home's "Because you liked" shelf. Tapping a book offers to request it through ReadMeABook.
struct SirenBecauseYouLikedShelf: View {
  var onConnect: () -> Void
  @State private var recommendations = SirenRecommendations.shared
  @State private var requests = SirenRequests.shared
  @State private var selected: AudibleProduct?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if let seed = recommendations.seedTitle, !recommendations.picks.isEmpty {
        SirenSectionHeader(title: "Because you liked \(seed)")
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(alignment: .top, spacing: 14) {
            ForEach(recommendations.picks) { product in
              Button {
                selected = product
              } label: {
                SirenRatedCard(book: book(product), caption: isRequested(product) ? "Requested" : nil)
              }
              .buttonStyle(.plain)
            }
          }
        }
        .scrollClipDisabled()
      }
    }
    .confirmationDialog(
      selected?.title ?? "",
      isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
      titleVisibility: .visible,
      presenting: selected
    ) { product in
      if isRequested(product) {
        // Nothing to do; the dialog just says so.
      } else if requests.isConnected {
        Button("Request") { request(product) }
      } else {
        Button("Connect ReadMeABook", action: onConnect)
      }
    } message: { product in
      Text(message(product))
    }
  }

  private func book(_ product: AudibleProduct) -> SirenBook {
    var book = SirenBook(id: product.asin, title: product.title, author: product.author, coverURL: product.coverURL)
    book.apply(product.rating)
    book.inLibrary = false
    return book
  }

  private func isRequested(_ product: AudibleProduct) -> Bool {
    requests.requests.contains { $0.audiobook.audibleAsin == product.asin && !$0.status.canRequestAgain }
  }

  private func message(_ product: AudibleProduct) -> String {
    var parts = [product.author]
    if let rating = product.rating {
      parts.append(
        String(
          localized:
            "Rated \(rating.average.formatted(.number.precision(.fractionLength(1)))) on Audible by \(rating.count.formatted()) listeners"
        )
      )
    }
    if isRequested(product) {
      parts.append(String(localized: "Already requested."))
    } else if !requests.isConnected {
      parts.append(String(localized: "Connect ReadMeABook to request books you don't have."))
    }
    return parts.filter { !$0.isEmpty }.joined(separator: "\n")
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

/// Home's shelf of unstarted books in the library that Audible's listeners rate highly.
struct SirenHighlyRatedShelf: View {
  var onOpen: (SirenBook) -> Void
  @State private var recommendations = SirenRecommendations.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if !recommendations.unstarted.isEmpty {
        SirenSectionHeader(title: "Highly Rated in Your Library")
        ScrollView(.horizontal, showsIndicators: false) {
          LazyHStack(alignment: .top, spacing: 14) {
            ForEach(recommendations.unstarted) { book in
              Button {
                onOpen(book)
              } label: {
                SirenRatedCard(book: book)
              }
              .buttonStyle(.plain)
            }
          }
        }
        .scrollClipDisabled()
      }
    }
  }
}

/// A cover, its title, and Audible's rating (or a caption in its place).
struct SirenRatedCard: View {
  let book: SirenBook
  var caption: String?
  var side: CGFloat = 120

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      RevealCover(book: book, progress: 0)
        .frame(width: side, height: side)
      Text(book.title)
        .font(SirenType.bookTitle(.footnote))
        .foregroundStyle(SirenTheme.ink)
        .multilineTextAlignment(.leading)
        .lineLimit(2, reservesSpace: true)
      if let caption {
        Text(caption)
          .font(.caption.weight(.semibold))
          .foregroundStyle(SirenTheme.secondary)
      } else if book.rating > 0 {
        StarRating(rating: book.rating, count: book.ratingCount, compact: true)
      }
    }
    .frame(width: side, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}
