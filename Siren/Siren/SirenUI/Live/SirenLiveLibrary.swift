import API
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
    SirenBookGrid(model: books, isFiltered: progressFilter != .all)
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
              books.onSortOptionTapped(option)
            } label: {
              if books.currentSort == option {
                Label(option.displayTitle, systemImage: books.ascending ? "chevron.up" : "chevron.down")
              } else {
                Text(option.displayTitle)
              }
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
      if books.showCollapseSeries {
        Toggle("Collapse Series", systemImage: "square.stack", isOn: $preferences.collapseSeriesInLibrary)
      }
    } label: {
      Label(
        "Sort and filter",
        systemImage: progressFilter == .all
          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
      )
    }
  }
}
