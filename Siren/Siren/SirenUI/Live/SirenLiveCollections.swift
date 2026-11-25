import SwiftUI

/// The books of a series, narrator, genre, tag or author's library, over upstream's
/// `LibraryPageModel(destination:)`.
struct SirenLiveBookList: View {
  @StateObject private var model: LibraryPage.Model
  @State private var confirmsDownloadAll = false

  init(destination: NavigationDestination) {
    _model = StateObject(wrappedValue: LibraryPageModel(destination: destination))
  }

  var body: some View {
    SirenBookGrid(model: model)
      .queueChoiceDialog($model.queueChoice, onSelect: model.onQueueChoiceSelected)
      .confirmationDialog("Download All Books", isPresented: $confirmsDownloadAll, titleVisibility: .visible) {
        Button("Download All", action: model.onDownloadAllTapped)
      } message: {
        Text("This downloads every book in this list and may use a lot of storage.")
      }
      .navigationTitle(model.title)
      .navigationBarTitleDisplayMode(.large)
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          if model.actions.contains(.playAll), !model.items.isEmpty {
            Button("Play All", systemImage: "play.fill", action: model.onPlayAllTapped)
          }
          moreMenu
        }
      }
  }

  private var moreMenu: some View {
    Menu {
      if !model.sortOptions.isEmpty {
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
      }
      Section {
        Button("Download All…", systemImage: "arrow.down.circle") { confirmsDownloadAll = true }
        if model.actions.contains(.markAsFinished) {
          Button("Mark All as Finished", systemImage: "checkmark.circle", action: model.onMarkAllFinishedTapped)
        }
        if model.actions.contains(.resetProgress) {
          Button("Reset All Progress", systemImage: "arrow.counterclockwise", action: model.onResetAllProgressTapped)
        }
      }
    } label: {
      Label("More", systemImage: "ellipsis")
    }
  }
}

/// An author: photo, bio, their series as shelves, then every book.
struct SirenLiveAuthor: View {
  @StateObject private var model: AuthorDetailsView.Model
  @State private var router = SirenRouter.shared

  private let columns = [
    GridItem(.adaptive(minimum: 100, maximum: 170), spacing: 14, alignment: .top)
  ]

  init(id: String, name: String, libraryID: String?) {
    _model = StateObject(wrappedValue: AuthorDetailsViewModel(authorID: id, name: name, libraryID: libraryID))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        header
        if let bio {
          SirenExpandableText(text: bio, lineLimit: 5)
        }
        ForEach(model.series) { series in
          SirenSectionHeader(title: series.name)
          SirenCoverShelf(books: series.books.map(SirenBook.init(card:))) { book in
            router.push(NavigationDestination.book(id: book.id))
          }
        }
        if !model.allBooks.isEmpty {
          SirenSectionHeader(title: "All Books")
          LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
            ForEach(model.allBooks, id: \.id) { card in
              NavigationLink(value: NavigationDestination.book(id: card.id)) {
                SirenLibraryCell(book: SirenBook(card: card))
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 32)
    }
    .background(SirenTheme.ground)
    .navigationTitle(model.name)
    .navigationBarTitleDisplayMode(.inline)
    .overlay {
      if model.isLoading, model.allBooks.isEmpty {
        ProgressView()
      } else if let error = model.error {
        ContentUnavailableView {
          Label("Couldn't load this author", systemImage: "exclamationmark.triangle")
        } description: {
          Text(error)
        } actions: {
          Button("Try Again", action: model.onAppear)
        }
        .background(SirenTheme.ground)
      }
    }
    .onAppear(perform: model.onAppear)
  }

  private var header: some View {
    HStack(spacing: 16) {
      SirenAuthorPhoto(name: model.name, url: model.imageURL, side: 88)
      VStack(alignment: .leading, spacing: 4) {
        Text(model.name)
          .font(.title2.weight(.bold))
          .foregroundStyle(SirenTheme.ink)
          .accessibilityAddTraits(.isHeader)
        if let count = model.bookCount, count > 0 {
          Text(count == 1 ? "1 book" : "\(count) books")
            .font(.subheadline)
            .foregroundStyle(SirenTheme.secondary)
        }
      }
    }
    .padding(.top, 8)
  }

  private var bio: String? {
    guard let description = model.description else { return nil }
    let text = SirenText.plain(html: description)
    return text.isEmpty ? nil : text
  }
}
