import SwiftUI

/// Search bound to upstream's `SearchViewModel`: books first, then series, authors, narrators,
/// genres and tags.
struct SirenLiveSearch: View {
  @StateObject private var model: SearchView.Model = SearchViewModel()

  var body: some View {
    List {
      if !model.books.isEmpty {
        Section("Books") {
          ForEach(model.books, id: \.id) { card in
            NavigationLink(value: NavigationDestination.book(id: card.id)) {
              SirenSearchBookRow(book: SirenBook(card: card))
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
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(SirenTheme.ground)
    .scrollDismissesKeyboard(.interactively)
    .navigationTitle("Search")
    .searchable(text: $model.searchText, prompt: "Books, authors, series")
    .onChange(of: model.searchText) { _, text in model.onSearchChanged(text) }
    .overlay {
      if model.isLoading, isEmpty {
        ProgressView()
      } else if !model.searchText.isEmpty, isEmpty {
        ContentUnavailableView.search(text: model.searchText)
      }
    }
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
    .padding(.vertical, 2)
  }
}
