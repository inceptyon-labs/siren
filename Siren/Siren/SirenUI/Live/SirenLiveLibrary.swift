import API
import SirenKit
import SwiftUI

/// Library bound to upstream's `LibraryPageModel`. Books are Siren's grid; Series and Authors are
/// upstream's pages until Siren draws its own.
struct SirenLiveLibrary: View {
  @StateObject private var books: LibraryPage.Model = LibraryPageModel()
  @StateObject private var series: SeriesPage.Model = SeriesPageModel()
  @StateObject private var authors: AuthorsPage.Model = AuthorsPageModel()
  @ObservedObject private var libraries = Audiobookshelf.shared.libraries
  @ObservedObject private var preferences = UserPreferences.shared

  @State private var scope: SirenLibraryScope = .books
  @State private var progressFilter: ProgressFilter = .all
  @AppStorage(SirenSettings.sortByRating) private var sortsByRating = false
  @AppStorage(SirenSettings.minimumRating) private var minimumRating = 0.0

  /// Audiobookshelf can't sort or filter by a rating it doesn't store, so these load the whole
  /// library on the device.
  private var usesRatings: Bool { sortsByRating || minimumRating > 0 }

  /// Audiobookshelf's progress filter values.
  private enum ProgressFilter: String, CaseIterable, Identifiable {
    case all = ""
    case inProgress = "In Progress"
    case notStarted = "Not Started"
    case finished = "Finished"

    var id: Self { self }

    init(_ saved: FilterPicker.Model.Filter) {
      if case .progress(let value) = saved, let match = Self(rawValue: value) {
        self = match
      } else {
        self = .all
      }
    }

    var filter: FilterPicker.Model.Filter {
      self == .all ? .all : .progress(rawValue)
    }

    var title: LocalizedStringKey {
      switch self {
      case .all: "All books"
      case .inProgress: "In progress"
      case .notStarted: "Not started"
      case .finished: "Finished"
      }
    }
  }

  var body: some View {
    Group {
      switch scope {
      case .books: booksGrid
      case .series: SirenSeriesGrid(model: series)
      case .authors: SirenAuthorList(model: authors)
      }
    }
    .safeAreaInset(edge: .top, spacing: 0) {
      Picker("Browse by", selection: $scope) {
        ForEach(SirenLibraryScope.allCases) { option in
          Text(option.title).tag(option)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(.horizontal, 20)
      .padding(.vertical, 8)
      .background(SirenTheme.ground)
    }
    .background(SirenTheme.ground)
    .navigationTitle("Library")
    .navigationBarTitleDisplayMode(.large)
  }

  private var booksGrid: some View {
    Group {
      if usesRatings {
        SirenRatedGrid(
          query: SirenRatedGrid.Query(
            libraryID: libraries.current?.id,
            filter: progressFilter.filter.queryValue,
            sort: books.currentSort,
            ascending: books.ascending,
            byRating: sortsByRating,
            minimum: minimumRating
          )
        )
      } else {
        SirenBookGrid(model: books, isFiltered: progressFilter != .all)
      }
    }
    .onAppear {
      // Siren's menu only offers progress filters; drop any other saved filter so the grid
      // never looks unfiltered while it isn't.
      progressFilter = ProgressFilter(preferences.libraryFilter)
      if preferences.libraryFilter != progressFilter.filter {
        preferences.libraryFilter = .all
        books.onFilterPreferenceChanged(.all)
      }
    }
    .onChange(of: preferences.collapseSeriesInLibrary) { _, _ in
      books.onCollapseSeriesToggled()
    }
    .onChange(of: progressFilter) { _, filter in
      preferences.libraryFilter = filter.filter
      books.onFilterPreferenceChanged(filter.filter)
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) { sortMenu }
    }
  }

  private var sortMenu: some View {
    Menu {
      if !books.sortOptions.isEmpty {
        Section("Sort by") {
          ForEach(books.sortOptions, id: \.self) { option in
            Button {
              // Leaving the rating sort keeps the server's current direction.
              if sortsByRating, books.currentSort == option {
                sortsByRating = false
              } else {
                sortsByRating = false
                books.onSortOptionTapped(option)
              }
            } label: {
              if !sortsByRating, books.currentSort == option {
                Label(option.displayTitle, systemImage: books.ascending ? "chevron.up" : "chevron.down")
              } else {
                Text(option.displayTitle)
              }
            }
          }
          Button {
            sortsByRating = true
          } label: {
            if sortsByRating {
              Label("Audible Rating", systemImage: "chevron.down")
            } else {
              Text("Audible Rating")
            }
          }
        }
      }
      Section("Show") {
        Picker("Show", selection: $progressFilter) {
          ForEach(ProgressFilter.allCases) { option in
            Text(option.title).tag(option)
          }
        }
      }
      Section("Audible rating") {
        Picker("Audible rating", selection: $minimumRating) {
          Text("Any rating").tag(0.0)
          Text("4 stars and up").tag(4.0)
          Text("4.5 stars and up").tag(4.5)
        }
      }
      // The rated grid shows every book on its own.
      if books.showCollapseSeries, !usesRatings {
        Toggle("Collapse Series", systemImage: "square.stack", isOn: $preferences.collapseSeriesInLibrary)
      }
    } label: {
      Label(
        "Sort and filter",
        systemImage: progressFilter == .all && minimumRating == 0
          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
      )
    }
  }
}

/// The library sorted or filtered by Audible rating. It loads every book in the library, in the
/// server's order for the current sort, then their ratings, and shows them once the ratings are in.
struct SirenRatedGrid: View {
  struct Query: Hashable {
    let libraryID: String?
    /// Audiobookshelf's progress filter.
    let filter: String?
    let sort: SortBy?
    let ascending: Bool
    let byRating: Bool
    let minimum: Double

    /// The part Audiobookshelf answers; rating sort and filter happen on the device.
    var source: Source { Source(libraryID: libraryID, filter: filter, sort: sort, ascending: ascending) }
  }

  struct Source: Hashable {
    let libraryID: String?
    let filter: String?
    let sort: SortBy?
    let ascending: Bool
  }

  let query: Query

  /// Every book in the library, in the server's order, and the request they came from.
  @State private var all: [SirenBook] = []
  @State private var loadedFrom: Source?
  /// Bumped by every load, so an older one (a refresh, say) can't land over a newer one.
  @State private var generation = 0
  @State private var isLoading = true
  @State private var error: String?

  private static let columns = [GridItem(.adaptive(minimum: 100, maximum: 170), spacing: 14, alignment: .top)]

  var body: some View {
    let books = books
    ScrollView {
      LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 22) {
        ForEach(books) { book in
          NavigationLink(value: NavigationDestination.book(id: book.id)) {
            SirenLibraryCell(book: book, showsRating: true)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 4)
    }
    .background(SirenTheme.ground)
    .overlay {
      if books.isEmpty {
        if isLoading {
          ProgressView("Loading ratings…")
        } else if let error {
          ContentUnavailableView(
            "Couldn't Load the Library",
            systemImage: "exclamationmark.triangle",
            description: Text(error)
          )
        } else {
          ContentUnavailableView(
            "No books",
            systemImage: "books.vertical",
            description: Text("Nothing matches this filter.")
          )
        }
      }
    }
    .refreshable { await load() }
    .task(id: query.source) { await load() }
  }

  /// Rated and filtered, and sorted when sorting by rating.
  private var books: [SirenBook] {
    var books = all.map { book in
      var book = book
      book.apply(AudibleRatings.shared.rating(for: book.asin))
      return book
    }
    if query.minimum > 0 {
      // As Audible shows it: 4.46 reads as 4.5.
      books = books.filter { ($0.rating * 10).rounded() / 10 >= query.minimum }
    }
    if query.byRating {
      // Unrated books last; ties keep the server's order.
      books = books.enumerated()
        .sorted { lhs, rhs in
          if lhs.element.rating != rhs.element.rating { return lhs.element.rating > rhs.element.rating }
          if lhs.element.ratingCount != rhs.element.ratingCount {
            return lhs.element.ratingCount > rhs.element.ratingCount
          }
          return lhs.offset < rhs.offset
        }
        .map(\.element)
    }
    return books
  }

  private func load() async {
    let source = query.source
    generation += 1
    let current = generation
    // Books from another filter or sort would contradict the menu, so they go; a refresh keeps them.
    if loadedFrom != source {
      all = []
      loadedFrom = nil
    }
    isLoading = true
    do {
      let page = try await Audiobookshelf.shared.books.fetch(
        sortBy: source.sort,
        ascending: source.ascending,
        filter: source.filter,
        libraryID: source.libraryID
      )
      let fetched = page.results.map(SirenBook.init(book:))
      await AudibleRatings.shared.load(fetched.compactMap(\.asin))
      guard generation == current else { return }
      all = fetched
      loadedFrom = source
      error = nil
    } catch {
      guard generation == current else { return }
      self.error = error.localizedDescription
    }
    isLoading = false
  }
}
