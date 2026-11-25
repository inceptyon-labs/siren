import API
import NukeUI
import SwiftUI

private let sirenGridColumns = [
  GridItem(.adaptive(minimum: 100, maximum: 170), spacing: 14, alignment: .top)
]

/// A paged cover grid over upstream's `LibraryPage.Model`: the library, a series, a narrator,
/// a genre or a tag.
struct SirenBookGrid: View {
  @ObservedObject var model: LibraryPage.Model
  var isFiltered = false

  var body: some View {
    ScrollView {
      LazyVGrid(columns: sirenGridColumns, alignment: .leading, spacing: 22) {
        ForEach(model.items) { item in
          switch item {
          case .book(let card):
            NavigationLink(value: NavigationDestination.book(id: card.id)) {
              SirenLibraryCell(book: SirenBook(card: card))
            }
            .buttonStyle(.plain)
          case .series(let series):
            NavigationLink(value: NavigationDestination.series(id: series.id, name: series.title)) {
              SirenSeriesTile(series: series)
            }
            .buttonStyle(.plain)
          }
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 4)

      if model.hasMorePages {
        PaginationFooter(hasError: model.pageLoadFailed, onLoadMore: model.loadNextPageIfNeeded)
      }
    }
    .background(SirenTheme.ground)
    .overlay {
      if model.items.isEmpty {
        if model.isLoading {
          ProgressView()
        } else if isFiltered {
          ContentUnavailableView(
            "No books",
            systemImage: "books.vertical",
            description: Text("Nothing matches this filter.")
          )
        }
      }
    }
    .refreshable { await model.refresh() }
    .onAppear(perform: model.onAppear)
  }
}

/// A series: its first cover on a short stack of sketches, with its name and size.
struct SirenSeriesTile: View {
  let series: SeriesCard.Model

  var body: some View {
    let book = SirenBook(series: series)
    VStack(alignment: .leading, spacing: 8) {
      RevealCover(book: book)
        .background(alignment: .topTrailing) {
          ForEach([2, 1], id: \.self) { layer in
            RoundedRectangle(cornerRadius: SirenTheme.coverRadius, style: .continuous)
              .fill(SirenTheme.paper)
              .overlay {
                RoundedRectangle(cornerRadius: SirenTheme.coverRadius, style: .continuous)
                  .strokeBorder(SirenTheme.graphite.opacity(0.25), lineWidth: 0.5)
              }
              .offset(x: CGFloat(layer) * 4, y: CGFloat(layer) * -4)
          }
        }
        .padding(.top, 8)
        .padding(.trailing, 8)
      VStack(alignment: .leading, spacing: 2) {
        Text(series.title)
          .font(SirenType.bookTitle(.footnote))
          .foregroundStyle(SirenTheme.ink)
          .multilineTextAlignment(.leading)
          .lineLimit(2, reservesSpace: true)
        Text(book.author)
          .font(.caption)
          .foregroundStyle(SirenTheme.secondary)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("\(series.title), series, \(book.author)"))
  }
}

/// The Library's Series scope over upstream's `SeriesPageModel`.
struct SirenSeriesGrid: View {
  @ObservedObject var model: SeriesPage.Model

  var body: some View {
    ScrollView {
      LazyVGrid(columns: sirenGridColumns, alignment: .leading, spacing: 22) {
        ForEach(model.series, id: \.id) { series in
          NavigationLink(value: NavigationDestination.series(id: series.id, name: series.title)) {
            SirenSeriesTile(series: series)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 4)

      if model.hasMorePages {
        PaginationFooter(hasError: model.pageLoadFailed, onLoadMore: model.loadNextPageIfNeeded)
      }
    }
    .background(SirenTheme.ground)
    .overlay {
      if model.series.isEmpty, model.isLoading { ProgressView() }
    }
    .refreshable { await model.refresh() }
    .onAppear(perform: model.onAppear)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Menu {
          Section("Sort by") {
            ForEach(model.sortOptions, id: \.self) { option in
              Button {
                model.onSortOptionTapped(option)
              } label: {
                if model.currentSort == option {
                  Label(option.displayTitle, systemImage: model.ascending ? "chevron.up" : "chevron.down")
                } else {
                  Text(option.displayTitle)
                }
              }
            }
          }
        } label: {
          Label("Sort", systemImage: "arrow.up.arrow.down.circle")
        }
      }
    }
  }
}

/// The Library's Authors scope over upstream's `AuthorsPageModel`, A to Z.
struct SirenAuthorList: View {
  @ObservedObject var model: AuthorsPage.Model

  var body: some View {
    List {
      ForEach(model.sections) { section in
        Section(section.letter) {
          ForEach(section.authors, id: \.id) { author in
            NavigationLink(value: NavigationDestination.author(id: author.id, name: author.name)) {
              SirenAuthorRow(author: author)
            }
            .listRowBackground(SirenTheme.raised)
          }
        }
      }
      if model.hasMorePages {
        PaginationFooter(hasError: model.pageLoadFailed, onLoadMore: model.loadNextPageIfNeeded)
          .listRowBackground(Color.clear)
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(SirenTheme.ground)
    .overlay {
      if model.sections.isEmpty, model.isLoading { ProgressView() }
    }
    .refreshable { await model.refresh() }
    .onAppear(perform: model.onAppear)
  }
}

struct SirenAuthorRow: View {
  let author: AuthorCard.Model

  var body: some View {
    HStack(spacing: 12) {
      SirenAuthorPhoto(name: author.name, url: author.imageURL, side: 40)
      VStack(alignment: .leading, spacing: 1) {
        Text(author.name)
          .foregroundStyle(SirenTheme.ink)
        if author.bookCount > 0 {
          Text(author.bookCount == 1 ? "1 book" : "\(author.bookCount) books")
            .font(.footnote)
            .foregroundStyle(SirenTheme.secondary)
        }
      }
    }
    .padding(.vertical, 2)
  }
}

/// An author's photo, or their initials on paper when the server has none.
struct SirenAuthorPhoto: View {
  let name: String
  let url: URL?
  var side: CGFloat = 40

  private var initials: String {
    name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
  }

  var body: some View {
    ZStack {
      SirenTheme.paper
      Text(initials)
        .font(.system(size: side * 0.38, weight: .semibold))
        .foregroundStyle(SirenTheme.graphite)
      if let url {
        LazyImage(url: url) { state in
          state.image?.resizable().scaledToFill()
        }
      }
    }
    .frame(width: side, height: side)
    .clipShape(Circle())
    .overlay { Circle().strokeBorder(.black.opacity(0.08), lineWidth: 0.5) }
    .accessibilityHidden(true)
  }
}
