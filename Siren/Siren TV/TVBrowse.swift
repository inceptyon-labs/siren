import API
import SirenKit
import SwiftUI

/// Home: what's playing, then the server's own shelves (Continue Listening, Recently Added and the
/// rest), with your progress on each cover.
struct TVHome: View {
  @State private var shelves: [Shelf] = []
  @State private var progress: [String: Double] = [:]
  @State private var failure: String?
  @State private var isLoading = true
  @State private var player = TVPlayer.shared

  struct Shelf: Identifiable {
    let id: String
    let title: String
    let books: [TVItem]
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 56) {
        if let book = player.book {
          TVNowPlayingRow(book: book)
        }
        ForEach(shelves) { shelf in
          TVShelfRow(title: shelf.title, books: shelf.books, progress: progress)
        }
        if isLoading, shelves.isEmpty {
          ProgressView().frame(maxWidth: .infinity)
        } else if let failure {
          TVMessage(title: "Couldn't load your library", detail: failure) { Task { await load() } }
        } else if shelves.isEmpty {
          TVMessage(title: "Nothing here yet", detail: "Books you add to Audiobookshelf show up here.")
        }
      }
      .padding(.vertical, 40)
    }
    .task { await load() }
  }

  private func load() async {
    #if DEBUG
    if let demo = TVDemo.shelves {
      (shelves, progress, isLoading) = (demo, TVDemo.progress, false)
      return
    }
    #endif
    isLoading = true
    defer { isLoading = false }
    await TVLibraryChoice.ensure()
    do {
      let personalized = try await Audiobookshelf.shared.libraries.fetchPersonalized()
      shelves = personalized.sections.compactMap { section in
        guard case .books(let books) = section.entities, !books.isEmpty else { return nil }
        return Shelf(id: section.id, title: section.label, books: books.map(TVItem.init))
      }
      failure = nil
    } catch {
      failure = error.localizedDescription
    }
    if let mine = try? await MyProgress.books() {
      progress = Dictionary(mine.map { ($0.libraryItemId, $0.isFinished ? 1 : $0.progress) }, uniquingKeysWith: max)
    }
    TVTopShelf.publish(shelves.first { $0.id == "continue-listening" }?.books ?? [], progress: progress)
  }
}

/// Every book in the library, by title.
struct TVLibrary: View {
  @State private var books: [TVItem] = []
  @State private var progress: [String: Double] = [:]
  @State private var failure: String?
  @State private var isLoading = true

  nonisolated private struct Items: Decodable, Sendable {
    let results: [Book]
  }

  var body: some View {
    ScrollView {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 280), spacing: 48)], spacing: 56) {
        ForEach(books) { book in
          TVBookCard(book: book, progress: progress[book.id])
        }
      }
      .padding(.vertical, 40)
      if isLoading, books.isEmpty {
        ProgressView()
      } else if let failure {
        TVMessage(title: "Couldn't load your library", detail: failure) { Task { await load() } }
      }
    }
    .task { await load() }
  }

  private func load() async {
    #if DEBUG
    if let demo = TVDemo.shelves {
      (books, progress, isLoading) = (demo.flatMap(\.books), TVDemo.progress, false)
      return
    }
    #endif
    isLoading = true
    defer { isLoading = false }
    await TVLibraryChoice.ensure()
    guard let library = Audiobookshelf.shared.libraries.current else { return }
    do {
      let items: Items = try await Audiobookshelf.shared.send(
        "/api/libraries/\(library.id)/items",
        query: ["minified": "1", "sort": "media.metadata.title"]
      )
      books = items.results.map(TVItem.init)
      failure = nil
    } catch {
      failure = error.localizedDescription
    }
    if let mine = try? await MyProgress.books() {
      progress = Dictionary(mine.map { ($0.libraryItemId, $0.isFinished ? 1 : $0.progress) }, uniquingKeysWith: max)
    }
  }
}

struct TVShelfRow: View {
  let title: String
  let books: [TVItem]
  let progress: [String: Double]

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.title3.weight(.semibold))
        .foregroundStyle(SirenTheme.secondary)
      ScrollView(.horizontal) {
        LazyHStack(alignment: .top, spacing: 48) {
          ForEach(books) { book in
            TVBookCard(book: book, progress: progress[book.id])
          }
        }
        .padding(.vertical, 32)
      }
      .scrollClipDisabled()
    }
    .focusSection()
  }
}

/// A book as the TV's shelves show it.
struct TVItem: Identifiable, Hashable {
  let id: String
  let title: String
  let coverURL: URL?
}

extension TVItem {
  init(_ book: Book) {
    self.init(id: book.id, title: book.title, coverURL: book.coverURL())
  }
}

/// A cover that plays the book, with its title and how far you are under it.
struct TVBookCard: View {
  let book: TVItem
  var progress: Double?

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Button {
        Task { await TVPlayer.shared.play(itemID: book.id) }
      } label: {
        TVCover(url: book.coverURL, title: book.title)
          .frame(width: 260, height: 260)
      }
      .buttonStyle(.card)
      .accessibilityLabel(book.title)
      Text(book.title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(SirenTheme.ink)
        .lineLimit(1)
      TVProgressLine(progress: progress)
    }
    .frame(width: 260)
  }
}

struct TVProgressLine: View {
  let progress: Double?

  var body: some View {
    if let progress, progress >= 1 {
      Text("Finished").font(.caption2).foregroundStyle(SirenTheme.secondary)
    } else if let progress, progress > 0 {
      ProgressView(value: progress).tint(SirenTheme.tint)
    } else {
      Text(" ").font(.caption2)
    }
  }
}

/// The server's cover, or the title on a plain plate while it loads or if there is none.
struct TVCover: View {
  let url: URL?
  let title: String

  var body: some View {
    AsyncImage(url: url) { image in
      image.resizable().scaledToFill()
    } placeholder: {
      ZStack {
        SirenTheme.raised
        Text(title)
          .font(SirenType.bookTitle(.headline))
          .foregroundStyle(SirenTheme.secondary)
          .multilineTextAlignment(.center)
          .padding(20)
      }
    }
    .clipped()
  }
}

/// The book playing now, at the top of Home: select it to open the player.
struct TVNowPlayingRow: View {
  let book: TVPlayer.Book
  @State private var player = TVPlayer.shared

  var body: some View {
    Button {
      player.isShowing = true
    } label: {
      HStack(spacing: 32) {
        TVCover(url: book.coverURL, title: book.title)
          .frame(width: 160, height: 160)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        VStack(alignment: .leading, spacing: 8) {
          Text(player.isPlaying ? "Now Playing" : "Paused")
            .font(.caption.weight(.semibold))
            .foregroundStyle(SirenTheme.tint)
          Text(book.title)
            .font(SirenType.bookTitle(.title2))
            .foregroundStyle(SirenTheme.ink)
            .lineLimit(1)
          if let chapter = player.chapter {
            Text(chapter.title).font(.callout).foregroundStyle(SirenTheme.secondary).lineLimit(1)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(24)
    }
    .buttonStyle(.card)
    .focusSection()
  }
}

struct TVMessage: View {
  let title: LocalizedStringKey
  let detail: String
  var retry: (() -> Void)?

  var body: some View {
    VStack(spacing: 16) {
      Text(title).font(.title3.weight(.semibold)).foregroundStyle(SirenTheme.ink)
      Text(detail).font(.callout).foregroundStyle(SirenTheme.secondary).multilineTextAlignment(.center)
      if let retry { Button("Try Again", action: retry) }
    }
    .frame(maxWidth: 900)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 60)
  }
}
