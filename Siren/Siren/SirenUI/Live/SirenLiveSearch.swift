import SirenKit
import SwiftUI

/// Search bound to upstream's `SearchViewModel`: books first, then series, authors, narrators,
/// genres and tags.
struct SirenLiveSearch: View {
  @StateObject private var model: SearchView.Model = SearchViewModel()
  @State private var requests = SirenRequests.shared
  @State private var scope: Scope = .library
  @State private var catalog: [ReadMeABook.SearchResult] = []
  @State private var catalogPage = 1
  /// The query the results on screen came from; More Results pages that one.
  @State private var catalogQuery = ""
  /// Bumped by every new search, so a page that loads after one is dropped.
  @State private var catalogGeneration = 0
  @State private var catalogHasMore = false
  @State private var isSearchingCatalog = false
  @State private var catalogError: String?

  private enum Scope: Hashable {
    case library, request
  }

  var body: some View {
    List {
      Section {
        Picker("Search in", selection: $scope) {
          Text("In Library").tag(Scope.library)
          Text("Request").tag(Scope.request)
        }
        .pickerStyle(.segmented)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
      }
      if scope == .request {
        requestResults
      } else {
        libraryResults
      }
    }
    .listStyle(.insetGrouped)
    .listSectionSpacing(.compact)
    .scrollContentBackground(.hidden)
    .background(SirenTheme.ground)
    .scrollDismissesKeyboard(.interactively)
    .navigationTitle("Search")
    .searchable(text: $model.searchText, prompt: scope == .request ? "Title or author" : "Books, authors, series")
    .onChange(of: scope) { _, scope in
      if scope == .library { model.onSearchChanged(model.searchText) }
    }
    .onChange(of: model.searchText) { _, text in
      if scope == .library { model.onSearchChanged(text) }
      // The results on screen are for the old text until the new search lands.
      catalogHasMore = false
    }
    .task(id: CatalogQuery(text: model.searchText, scope: scope)) { await searchCatalog() }
    .task(id: model.books.map(\.id)) { await AudibleRatings.shared.load(model.books.compactMap(\.asin)) }
    .onAppear { requests.sync() }
    .overlay {
      if scope == .request {
        requestOverlay
      } else if model.isLoading, isEmpty {
        ProgressView()
      } else if !model.searchText.isEmpty, isEmpty {
        ContentUnavailableView.search(text: model.searchText)
      }
    }
  }

  private struct CatalogQuery: Hashable {
    let text: String
    let scope: Scope
  }

  @ViewBuilder private var requestResults: some View {
    if !catalog.isEmpty || catalogHasMore {
      Section {
        ForEach(catalog) { result in
          SirenRequestResultRow(result: result)
            .listRowBackground(SirenTheme.raised)
        }
        if catalogHasMore {
          Button("More Results") { Task { await loadMoreCatalog() } }
            .disabled(isSearchingCatalog)
            .listRowBackground(SirenTheme.raised)
        }
      } footer: {
        Text("Requests go to ReadMeABook. Home shows how each one is going.")
      }
    }
  }

  @ViewBuilder private var requestOverlay: some View {
    if !requests.isConnected {
      ContentUnavailableView {
        Label("Request Books", systemImage: "tray.and.arrow.down")
      } description: {
        Text("Connect ReadMeABook to search the Audible catalog and request books you don't have.")
      } actions: {
        NavigationLink("Connect ReadMeABook", value: SirenRoute.requests)
      }
    } else if let catalogError, catalog.isEmpty {
      ContentUnavailableView("Search Failed", systemImage: "exclamationmark.triangle", description: Text(catalogError))
    } else if isSearchingCatalog, catalog.isEmpty, !catalogHasMore {
      ProgressView()
    } else if model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
      ContentUnavailableView(
        "Find a Book",
        systemImage: "magnifyingglass",
        description: Text("Search the Audible catalog. Books you don't have can be requested.")
      )
    } else if catalog.isEmpty, !catalogHasMore {
      ContentUnavailableView.search(text: model.searchText)
    }
  }

  private func searchCatalog() async {
    catalogGeneration += 1
    let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard scope == .request, let client = requests.client, !query.isEmpty else {
      catalog = []
      catalogHasMore = false
      return
    }
    // Typing pauses before searching; a new keystroke cancels this task.
    try? await Task.sleep(for: .milliseconds(400))
    guard !Task.isCancelled else { return }
    isSearchingCatalog = true
    defer { isSearchingCatalog = false }
    do {
      // ReadMeABook's language filter can empty a page that has more after it: skip ahead a few.
      var page = try await client.search(query)
      while page.results.isEmpty, page.hasMore, page.page < 5, !Task.isCancelled {
        page = try await client.search(query, page: page.page + 1)
      }
      guard !Task.isCancelled else { return }
      catalog = page.results
      catalogQuery = query
      catalogPage = page.page
      catalogHasMore = page.hasMore
      catalogError = nil
    } catch is CancellationError {
    } catch {
      guard !Task.isCancelled else { return }
      catalog = []
      catalogError = error.localizedDescription
    }
  }

  private func loadMoreCatalog() async {
    let query = catalogQuery
    let generation = catalogGeneration
    guard let client = requests.client, !query.isEmpty,
      model.searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query
    else { return }
    isSearchingCatalog = true
    defer { isSearchingCatalog = false }
    guard let page = try? await client.search(query, page: catalogPage + 1),
      // Still the same search: the text may have changed while this page loaded.
      generation == catalogGeneration, scope == .request,
      model.searchText.trimmingCharacters(in: .whitespacesAndNewlines) == query
    else { return }
    let known = Set(catalog.map(\.asin))
    catalog += page.results.filter { !known.contains($0.asin) }
    catalogPage = page.page
    catalogHasMore = page.hasMore
  }

  @ViewBuilder private var libraryResults: some View {
    if !model.books.isEmpty {
      Section("Books") {
        ForEach(model.books, id: \.id) { card in
          NavigationLink(value: NavigationDestination.book(id: card.id)) {
            SirenSearchBookRow(book: Self.book(card))
          }
          .listRowBackground(SirenTheme.raised)
        }
      }
    }
    if !model.series.isEmpty {
      Section("Series") {
        ForEach(model.series, id: \.id) { series in
          link(series.title, systemImage: "square.stack", to: .series(id: series.id, name: series.title))
        }
      }
    }
    if !model.authors.isEmpty {
      Section("Authors") {
        ForEach(model.authors, id: \.id) { author in
          link(author.name, systemImage: "person", to: .author(id: author.id, name: author.name))
        }
      }
    }
    if !model.narrators.isEmpty {
      Section("Narrators") {
        ForEach(model.narrators, id: \.self) { name in
          link(name, systemImage: "mic", to: .narrator(name: name))
        }
      }
    }
    if !model.genres.isEmpty {
      Section("Genres") {
        ForEach(model.genres, id: \.self) { name in
          link(name, systemImage: "theatermasks", to: .genre(name: name))
        }
      }
    }
    if !model.tags.isEmpty {
      Section("Tags") {
        ForEach(model.tags, id: \.self) { name in
          link(name, systemImage: "tag", to: .tag(name: name))
        }
      }
    }
  }

  private static func book(_ card: BookCard.Model) -> SirenBook {
    var book = SirenBook(card: card)
    book.apply(AudibleRatings.shared.rating(for: card.asin))
    return book
  }

  private var isEmpty: Bool {
    model.books.isEmpty && model.series.isEmpty && model.authors.isEmpty && model.narrators.isEmpty
      && model.genres.isEmpty && model.tags.isEmpty
  }

  private func link(_ title: String, systemImage: String, to destination: NavigationDestination) -> some View {
    NavigationLink(value: destination) {
      Label(title, systemImage: systemImage)
        .foregroundStyle(SirenTheme.ink)
    }
    .listRowBackground(SirenTheme.raised)
  }
}

private struct SirenSearchBookRow: View {
  let book: SirenBook

  var body: some View {
    HStack(spacing: 12) {
      RevealCover(book: book, cornerRadius: 4, shadow: false)
        .frame(width: 52, height: 52)
      VStack(alignment: .leading, spacing: 2) {
        Text(book.title)
          .font(SirenType.bookTitle(.headline))
          .foregroundStyle(SirenTheme.ink)
          .lineLimit(2)
        if !book.author.isEmpty {
          Text(book.author)
            .font(.subheadline)
            .foregroundStyle(SirenTheme.secondary)
            .lineLimit(1)
        }
        if book.rating > 0 || book.isStarted {
          HStack(spacing: 8) {
            if book.rating > 0 {
              StarRating(rating: book.rating, count: book.ratingCount, compact: true)
            }
            if book.isFinished {
              Text("Finished").font(.caption).foregroundStyle(SirenTheme.secondary)
            } else if book.isStarted {
              Text("\(Int((book.progress * 100).rounded()))% listened")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SirenTheme.tint)
                .monospacedDigit()
            }
          }
        }
      }
    }
    .padding(.vertical, 2)
  }
}
