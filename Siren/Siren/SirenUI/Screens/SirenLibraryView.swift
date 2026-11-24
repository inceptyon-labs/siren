import Foundation
import SwiftUI

struct SirenLibraryView: View {
  @State private var scope: SirenLibraryScope = .books
  @State private var sort: SirenLibrarySort = .recent
  @State private var shelfFilter: SirenLibraryFilter = .all

  private let columns = [
    GridItem(.adaptive(minimum: 100, maximum: 170), spacing: 14, alignment: .top)
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Picker("Browse by", selection: $scope) {
          ForEach(SirenLibraryScope.allCases) { option in
            Text(option.title).tag(option)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        if scope == .books {
          LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
            ForEach(books) { book in
              SirenLibraryCell(book: book)
            }
          }
        } else {
          ContentUnavailableView {
            Label {
              Text(scope.title)
            } icon: {
              Image(systemName: scope.symbol)
            }
          } description: {
            Text("Not in this demo build.")
          }
          .padding(.top, 40)
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 4)
      .padding(.bottom, 32)
    }
    .background(SirenTheme.ground)
    .navigationTitle("Library")
    .navigationBarTitleDisplayMode(.large)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        sortMenu
      }
    }
  }

  private var sortMenu: some View {
    Menu {
      Section("Sort by") {
        Picker("Sort by", selection: $sort) {
          ForEach(SirenLibrarySort.allCases) { option in
            Text(option.title).tag(option)
          }
        }
      }
      Section("Show") {
        Picker("Show", selection: $shelfFilter) {
          ForEach(SirenLibraryFilter.allCases) { option in
            Text(option.title).tag(option)
          }
        }
      }
    } label: {
      Label(
        "Sort and filter",
        systemImage: shelfFilter == .all
          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
    }
  }

  /// Demo.library repeats two titles from the finished shelf; show each book once.
  private var books: [DemoBook] {
    var seen = Set<String>()
    let shelf = Demo.library.filter { seen.insert($0.title).inserted }
    let shown = shelf.filter { shelfFilter.includes($0) }
    switch sort {
    case .recent:
      return shown
    case .byTitle:
      return shown.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    case .byAuthor:
      return shown.sorted { $0.author.localizedStandardCompare($1.author) == .orderedAscending }
    }
  }
}

private struct SirenLibraryCell: View {
  let book: DemoBook

  var body: some View {
    Button {} label: {
      VStack(alignment: .leading, spacing: 8) {
        RevealCover(book: book)
        VStack(alignment: .leading, spacing: 2) {
          Text(book.title)
            .font(SirenType.bookTitle(.footnote))
            .foregroundStyle(SirenTheme.ink)
            .multilineTextAlignment(.leading)
            .lineLimit(2, reservesSpace: true)
          Text(caption)
            .font(.caption)
            .foregroundStyle(SirenTheme.secondary)
            .monospacedDigit()
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text("\(book.title), \(book.author)"))
    .accessibilityValue(spokenStatus)
  }

  private var caption: String {
    if book.isFinished { return String(localized: "Finished") }
    if book.isStarted { return book.progress.formatted(.percent.precision(.fractionLength(0))) }
    let minutes = Int((book.hours * 60).rounded())
    return String(localized: "\(minutes / 60)h \(minutes % 60)m")
  }

  private var spokenStatus: String {
    if book.isFinished { return String(localized: "Finished") }
    if book.isStarted { return String(localized: "\(caption) listened") }
    let length = Duration.seconds(Int((book.hours * 3600).rounded()))
      .formatted(.units(allowed: [.hours, .minutes], width: .wide))
    return String(localized: "Not started, \(length)")
  }
}

private enum SirenLibraryScope: CaseIterable, Identifiable {
  case books, series, authors

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .books: "Books"
    case .series: "Series"
    case .authors: "Authors"
    }
  }

  var symbol: String {
    switch self {
    case .books: "books.vertical"
    case .series: "square.stack"
    case .authors: "person.2"
    }
  }
}

private enum SirenLibrarySort: CaseIterable, Identifiable {
  case recent, byTitle, byAuthor

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .recent: "Recently played"
    case .byTitle: "Title"
    case .byAuthor: "Author"
    }
  }
}

private enum SirenLibraryFilter: CaseIterable, Identifiable {
  case all, inProgress, notStarted, finished

  var id: Self { self }

  var title: LocalizedStringKey {
    switch self {
    case .all: "All books"
    case .inProgress: "In progress"
    case .notStarted: "Not started"
    case .finished: "Finished"
    }
  }

  func includes(_ book: DemoBook) -> Bool {
    switch self {
    case .all: true
    case .inProgress: book.isStarted && !book.isFinished
    case .notStarted: !book.isStarted
    case .finished: book.isFinished
    }
  }
}

#Preview {
  NavigationStack {
    SirenLibraryView()
  }
  .tint(SirenTheme.tint)
}
