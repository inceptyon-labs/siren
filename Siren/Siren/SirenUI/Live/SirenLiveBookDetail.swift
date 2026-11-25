import API
import SirenKit
import SwiftUI

/// Book detail bound to upstream's `BookDetailsViewModel`, with the rest of its series from
/// upstream's `LibraryPageModel`.
struct SirenLiveBookDetail: View {
  @StateObject private var model: BookDetailsView.Model
  @ObservedObject private var playerManager = PlayerManager.shared

  /// The library's books in this book's series, with their positions.
  @State private var ownedSeries: [(book: SirenBook, sequence: String?)] = []
  @State private var collectionSelector: CollectionMode?
  @State private var showingSend = false
  /// Nil until the "Liked" playlist has loaded.
  @State private var isLiked: Bool?
  @State private var isSavingLike = false
  /// Audible's list of the series, with the books the library doesn't have.
  @State private var audibleSeries: AudibleSeriesList?
  @State private var requesting: AudibleSeriesList.Book?
  @State private var profiles = SirenProfiles.shared
  @ObservedObject private var authentication = Audiobookshelf.shared.authentication

  private let coverSide: CGFloat = 220
  private let seriesCoverSide: CGFloat = 104

  init(bookID: String) {
    _model = StateObject(wrappedValue: BookDetailsViewModel(bookID: bookID))
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 28) {
        hero
        if let next = nextInSeries, let name = model.series.first?.name {
          SirenNextInSeriesCard(seriesName: name, next: next, canRequest: !profiles.isKidsActive) { requesting = $0 }
            .padding(.horizontal, 20)
        }
        if authentication.isSirenAdmin, let tags = model.tags, !HouseholdSend.recipients(in: tags).isEmpty {
          SirenSentProgress(itemID: model.bookID, tags: tags)
        }
        if !seriesEntries.isEmpty {
          seriesSection
        }
        if let about {
          aboutSection(about)
        }
        if chapters.count > 1 {
          chaptersSection
        }
        detailsSection
      }
      .padding(.bottom, 32)
      .frame(maxWidth: 720)
      .frame(maxWidth: .infinity)
    }
    .modifier(BookDetailNavigationTitle(title: model.title, revealOffset: coverSide + 44))
    .background(SirenTheme.ground)
    .navigationTitle(model.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) { likeButton }
      ToolbarItem(placement: .topBarTrailing) { moreMenu }
    }
    .overlay {
      if model.isLoading {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(SirenTheme.ground)
      } else if let error = model.error {
        ContentUnavailableView {
          Label("Couldn't load this book", systemImage: "exclamationmark.triangle")
        } description: {
          Text(error)
        } actions: {
          Button("Try Again", action: model.onAppear)
        }
        .background(SirenTheme.ground)
      }
    }
    .onAppear(perform: model.onAppear)
    .task(id: model.series.first?.id) {
      guard let series = model.series.first else {
        ownedSeries = []
        return
      }
      ownedSeries = await SirenSeriesResolver.owned(seriesID: series.id, name: series.name, libraryID: model.libraryID)
    }
    .task(id: model.bookID) { isLiked = (try? await Likes.likedIDs())?.contains(model.bookID) }
    .task(id: model.asin) {
      if let asin = model.asin { await AudibleRatings.shared.load([asin]) }
    }
    .task(id: SeriesLookup(asin: model.asin, name: model.series.first?.name)) {
      guard let asin = model.asin, let name = model.series.first?.name else {
        audibleSeries = nil
        return
      }
      let found = await AudibleSeries.shared.series(ofBook: asin, named: name)
      guard !Task.isCancelled else { return }
      audibleSeries = found
    }
    .sirenRequestDialog(
      for: Binding(get: { requesting?.product }, set: { if $0 == nil { requesting = nil } }),
      releaseDate: requesting?.isUpcoming == true ? requesting?.releaseDate : nil
    ) { SirenRouter.shared.push(SirenRoute.requests) }
    .fullScreenCover(item: $model.ebookReader) { reader in
      NavigationStack {
        EbookReaderView(model: reader)
      }
    }
    .sheet(isPresented: $showingSend) {
      SirenLiveSendSheet(book: book, onSent: model.onAppear)
        .presentationDetents([.fraction(0.75), .large])
        .presentationDragIndicator(.visible)
    }
    .sheet(item: $collectionSelector) { mode in
      CollectionSelectorSheet(model: CollectionSelectorSheetModel(bookID: model.bookID, mode: mode))
    }
    .sheet(
      isPresented: Binding(
        get: { model.bookmarks?.isPresented ?? false },
        set: { model.bookmarks?.isPresented = $0 }
      )
    ) {
      if let bookmarks = model.bookmarks {
        BookmarkViewerSheet(model: bookmarks)
      }
    }
  }

  // MARK: Book

  private var chapters: [ChaptersContent.Chapter] {
    for tab in model.tabs {
      if case .chapters(let content) = tab { return content.chapters }
    }
    return []
  }

  private var chaptersContent: ChaptersContent.Model? {
    for tab in model.tabs {
      if case .chapters(let content) = tab { return content }
    }
    return nil
  }

  private var book: SirenBook {
    if let current = playerManager.current, current.id == model.bookID {
      return SirenBook(player: current)
    }
    var book = SirenBook(
      id: model.bookID,
      title: model.title,
      author: model.authors.map(\.name).joined(separator: ", "),
      coverURL: model.coverURL
    )
    book.narrator = model.narrators.joined(separator: ", ")
    book.progress = model.progress.audio
    if let remaining = model.progressCard?.timeRemaining, book.isStarted {
      book.timeLeft = SirenFormat.span(remaining)
    }
    let chapters = chapters
    if chapters.count > 1, let total = chapters.last?.end {
      book.chapterCount = chapters.count
      book.chapterMarks = SirenBook.marks(chapters.map(\.start), total: total)
      if let index = chapters.firstIndex(where: { $0.status == .current }) {
        book.currentChapter = index + 1
        book.chapterTitle = chapters[index].title
      }
    }
    return book
  }

  // MARK: Hero

  private var hero: some View {
    let book = book
    return VStack(spacing: 0) {
      RevealCover(book: book, showTicks: book.chapterCount > 1, resolution: .large)
        .frame(width: coverSide, height: coverSide)
        .padding(.top, 8)

      Text(model.title)
        .font(SirenType.bookTitle(.title))
        .foregroundStyle(SirenTheme.ink)
        .multilineTextAlignment(.center)
        .padding(.top, 22)
        .accessibilityAddTraits(.isHeader)

      if let subtitle = model.subtitle, !subtitle.isEmpty {
        Text(subtitle)
          .font(.subheadline)
          .foregroundStyle(SirenTheme.secondary)
          .multilineTextAlignment(.center)
          .padding(.top, 2)
      }

      if !model.authors.isEmpty {
        HStack(spacing: 0) {
          ForEach(Array(model.authors.enumerated()), id: \.element.id) { index, author in
            NavigationLink(
              value: NavigationDestination.author(id: author.id, name: author.name, libraryID: model.libraryID)
            ) {
              Text(index == 0 ? author.name : ", \(author.name)")
            }
            .buttonStyle(.plain)
          }
        }
        .font(.body)
        .foregroundStyle(SirenTheme.ink)
        .padding(.top, 4)
      }

      if !book.narrator.isEmpty {
        Text("Read by \(book.narrator)")
          .font(.subheadline)
          .foregroundStyle(SirenTheme.secondary)
          .multilineTextAlignment(.center)
          .padding(.top, 2)
      }

      if let rating = AudibleRatings.shared.rating(for: model.asin) {
        SirenRatingSummary(
          rating: rating.average,
          count: rating.count,
          story: rating.story,
          performance: rating.performance
        )
        .padding(.top, 14)
      }

      actions(book)
        .padding(.top, 22)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 20)
  }

  private func actions(_ book: SirenBook) -> some View {
    VStack(spacing: 12) {
      if model.metadata.hasAudio {
        Button(action: model.onPlayTapped) {
          Label(playTitle(book), systemImage: model.isPlaying ? "pause.fill" : "play.fill")
            .monospacedDigit()
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
        }
        .buttonStyle(BookDetailCapsuleStyle(kind: .filled))
      } else if model.metadata.isEbook {
        Button(action: model.onReadTapped) {
          Label("Read", systemImage: "book")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BookDetailCapsuleStyle(kind: .filled))
      }

      HStack(spacing: 12) {
        downloadButton
        if model.metadata.hasAudio, model.metadata.isEbook {
          Button(action: model.onReadTapped) {
            Image(systemName: "book")
          }
          .buttonStyle(BookDetailCapsuleStyle(kind: .wash))
          .accessibilityLabel("Read")
        }
        if model.actions.contains(.viewBookmarks) {
          Button {
            model.bookmarks?.isPresented = true
          } label: {
            Image(systemName: "bookmark")
          }
          .buttonStyle(BookDetailCapsuleStyle(kind: .wash))
          .accessibilityLabel("Bookmarks")
        }
      }
    }
  }

  private func playTitle(_ book: SirenBook) -> String {
    if model.isPlaying { return "Pause" }
    if book.isFinished { return "Listen Again" }
    if book.isStarted {
      if book.chapterCount > 1, !book.chapterRemaining.isEmpty {
        return "Resume · Ch \(book.currentChapter) · \(book.chapterRemaining) left"
      }
      return book.timeLeft.isEmpty ? "Resume" : "Resume · \(book.timeLeft) left"
    }
    return "Play"
  }

  private var downloadButton: some View {
    Button(action: model.onDownloadTapped) {
      switch model.downloadState {
      case .notDownloaded:
        Label("Download", systemImage: "arrow.down.circle")
          .frame(maxWidth: .infinity)
      case .downloading(let progress):
        Label("Downloading \(Int((progress * 100).rounded()))%", systemImage: "stop.circle")
          .monospacedDigit()
          .frame(maxWidth: .infinity)
      case .downloaded:
        Label("Downloaded", systemImage: "checkmark.circle")
          .frame(maxWidth: .infinity)
      }
    }
    .buttonStyle(BookDetailCapsuleStyle(kind: .wash))
  }

  // MARK: Series

  private struct SeriesLookup: Hashable {
    let asin: String?
    let name: String?
  }

  /// The library's books in the series, merged with Audible's list once it's in.
  private var seriesEntries: [SirenSeriesEntry] {
    SirenSeriesEntry.merge(owned: ownedSeries, audible: audibleSeries)
  }

  /// Once this book is finished: the next one in the series you haven't finished, owned or not.
  private var nextInSeries: SirenSeriesEntry? {
    guard model.progress.audio >= 1 else { return nil }
    return SirenSeriesResolver.next(after: model.bookID, in: seriesEntries)
  }

  private var seriesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      SirenSectionHeader(title: model.series.first?.name ?? "")
        .padding(.horizontal, 20)
      ScrollView(.horizontal) {
        HStack(alignment: .top, spacing: 14) {
          ForEach(seriesEntries) { entry in
            switch entry {
            case .owned(let item, _): seriesItem(item)
            case .audible(let member): audibleSeriesItem(member)
            }
          }
        }
        .scrollTargetLayout()
      }
      .scrollIndicators(.hidden)
      .scrollTargetBehavior(.viewAligned)
      .contentMargins(.horizontal, 20, for: .scrollContent)
    }
  }

  private func seriesItem(_ item: SirenBook) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      if item.id == model.bookID {
        seriesTile(item)
      } else {
        NavigationLink(value: NavigationDestination.book(id: item.id)) {
          seriesTile(item)
        }
        .buttonStyle(.plain)
      }
      Text(seriesStatus(item))
        .font(item.isStarted && !item.isFinished ? Font.caption.weight(.semibold) : Font.caption)
        .foregroundStyle(item.isStarted && !item.isFinished ? SirenTheme.ink : SirenTheme.secondary)
        .monospacedDigit()
    }
    .frame(width: seriesCoverSide, alignment: .leading)
  }

  /// A book in the series the library doesn't have: tap to request it.
  private func audibleSeriesItem(_ member: AudibleSeriesList.Book) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        requesting = member
      } label: {
        seriesTile(SirenBook(audible: member.product))
      }
      .buttonStyle(.plain)
      // Requests are off in a kids profile.
      .allowsHitTesting(!profiles.isKidsActive)
      .accessibilityLabel("\(member.product.title), book \(member.sequence), not in your library")
      Text(audibleStatus(member))
        .font(.caption)
        .foregroundStyle(SirenTheme.secondary)
    }
    .frame(width: seriesCoverSide, alignment: .leading)
  }

  private func audibleStatus(_ member: AudibleSeriesList.Book) -> String {
    if let request = SirenRequests.shared.liveRequest(asin: member.product.asin) {
      return request.status.label(progress: request.progress, releaseDate: request.releaseDate)
    }
    return member.outLabel ?? String(localized: "Not in library")
  }

  private func seriesTile(_ item: SirenBook) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      RevealCover(book: item)
        .frame(width: seriesCoverSide, height: seriesCoverSide)
      Text(item.title)
        .font(SirenType.bookTitle(.subheadline))
        .foregroundStyle(SirenTheme.ink)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(item.seriesIndex.map { "\(item.title), book \($0)" } ?? item.title)
  }

  private func seriesStatus(_ item: SirenBook) -> String {
    if item.id == model.bookID { return "This book" }
    if item.isFinished { return "Finished" }
    if item.isStarted { return "\(Int((item.progress * 100).rounded()))% listened" }
    return "Not started"
  }

  // MARK: About, chapters, details

  private var about: String? {
    guard let description = model.description else { return nil }
    let text = SirenText.plain(html: description)
    return text.isEmpty ? nil : text
  }

  private func aboutSection(_ text: String) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      SirenSectionHeader(title: "About")
      SirenExpandableText(text: text, lineLimit: 6)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20)
  }

  private var chaptersSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SirenSectionHeader(title: "Chapters")
        .padding(.horizontal, 20)
      VStack(spacing: 0) {
        ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
          if index > 0 {
            Rectangle()
              .fill(SirenTheme.separator)
              .frame(height: 0.5)
              .padding(.leading, 16)
          }
          Button {
            chaptersContent?.onChapterTapped(chapter)
          } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
              Text("\(index + 1)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(chapter.status == .current ? SirenTheme.tint : SirenTheme.secondary)
                .monospacedDigit()
                .frame(minWidth: 22, alignment: .trailing)
              Text(chapter.title)
                .foregroundStyle(chapter.status == .completed ? SirenTheme.secondary : SirenTheme.ink)
                .fontWeight(chapter.status == .current ? .semibold : .regular)
                .multilineTextAlignment(.leading)
              Spacer(minLength: 12)
              Text(SirenFormat.clock(chapter.end - chapter.start))
                .font(.footnote)
                .foregroundStyle(SirenTheme.secondary)
                .monospacedDigit()
            }
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
      .background(SirenTheme.raised, in: RoundedRectangle(cornerRadius: SirenTheme.rowRadius, style: .continuous))
      .padding(.horizontal, 20)
    }
  }

  private struct DetailRow: Identifiable {
    let label: LocalizedStringKey
    let value: String
    var id: String { value }
  }

  private var detailRows: [DetailRow] {
    let metadata = model.metadata
    var rows: [DetailRow] = []
    if let duration = metadata.durationText { rows.append(DetailRow(label: "Length", value: duration)) }
    if chapters.count > 1 { rows.append(DetailRow(label: "Chapters", value: "\(chapters.count)")) }
    if let genres = model.genres, !genres.isEmpty {
      rows.append(DetailRow(label: "Genre", value: genres.joined(separator: ", ")))
    }
    if let year = metadata.publishedYear { rows.append(DetailRow(label: "Published", value: year)) }
    if let publisher = metadata.publisher { rows.append(DetailRow(label: "Publisher", value: publisher)) }
    if let language = metadata.language { rows.append(DetailRow(label: "Language", value: language)) }
    if model.flags.contains(.abridged) { rows.append(DetailRow(label: "Edition", value: "Abridged")) }
    return rows
  }

  @ViewBuilder private var detailsSection: some View {
    let rows = detailRows
    if !rows.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        SirenSectionHeader(title: "Details")
          .padding(.horizontal, 20)
        VStack(spacing: 0) {
          ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
            if index > 0 {
              Rectangle()
                .fill(SirenTheme.separator)
                .frame(height: 0.5)
                .padding(.leading, 16)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
              Text(row.label)
                .foregroundStyle(SirenTheme.ink)
              Spacer(minLength: 12)
              Text(row.value)
                .foregroundStyle(SirenTheme.secondary)
                .multilineTextAlignment(.trailing)
            }
            .font(.body)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .accessibilityElement(children: .combine)
          }
        }
        .background(SirenTheme.raised, in: RoundedRectangle(cornerRadius: SirenTheme.rowRadius, style: .continuous))
        .padding(.horizontal, 20)
      }
    }
  }

  // MARK: More

  /// Likes live in a private "Liked" playlist on the server; recommendations start from them.
  @ViewBuilder private var likeButton: some View {
    if let isLiked {
      Button(isLiked ? "Unlike" : "Like", systemImage: isLiked ? "heart.fill" : "heart") {
        let newValue = !isLiked
        self.isLiked = newValue
        isSavingLike = true
        Task {
          defer { isSavingLike = false }
          do {
            try await Likes.set(newValue, itemID: model.bookID)
          } catch {
            self.isLiked = !newValue
            Toast(error: "Couldn't save your like").show()
          }
        }
      }
      // One save at a time: each one reads the playlist, then changes it.
      .disabled(isSavingLike)
      .sensoryFeedback(.selection, trigger: isLiked)
    }
  }

  private var moreMenu: some View {
    Menu {
      if model.actions.contains(.addToQueue) {
        Button("Add to Queue", systemImage: "text.badge.plus", action: model.onAddToQueueTapped)
      }
      if model.actions.contains(.removeFromQueue) {
        Button("Remove from Queue", systemImage: "text.badge.minus", action: model.onRemoveFromQueueTapped)
      }
      if model.actions.contains(.addToCollection) {
        Button("Add to Collection", systemImage: "square.stack.3d.up") { collectionSelector = .collections }
      }
      Button("Add to Playlist", systemImage: "music.note.list") { collectionSelector = .playlists }
      if authentication.isSirenAdmin {
        Button("Send…", systemImage: "paperplane") { showingSend = true }
      }
      Section {
        if model.actions.contains(.markAsFinished) {
          Button("Mark as Finished", systemImage: "checkmark.circle", action: model.onMarkFinishedTapped)
        }
        if model.actions.contains(.resetProgress) {
          Button("Reset Progress", systemImage: "arrow.counterclockwise", action: model.onResetProgressTapped)
        }
      }
      Section {
        if model.actions.contains(.downloadToWatch) {
          Button("Download to Watch", systemImage: "applewatch", action: model.onDownloadToWatchTapped)
        }
        if model.actions.contains(.writeNFCTag) {
          Button("Write NFC Tag", systemImage: "wave.3.right", action: model.onWriteTagTapped)
        }
        if model.actions.contains(.sendToEbook) {
          ForEach(model.ereaderDevices, id: \.self) { device in
            Button("Send to \(device)", systemImage: "paperplane") { model.onSendToEbookTapped(device) }
          }
        }
      }
    } label: {
      Label("More", systemImage: "ellipsis")
    }
  }
}

enum SirenText {
  /// Audiobookshelf descriptions are HTML; Siren shows them as plain paragraphs.
  static func plain(html: String) -> String {
    var text = html
    for (pattern, replacement) in [
      ("(?i)<br\\s*/?>", "\n"),
      ("(?i)</p>\\s*", "\n\n"),
      ("(?i)</li>\\s*", "\n"),
      ("<[^>]+>", ""),
    ] {
      text = text.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
    for (entity, character) in [
      ("&nbsp;", " "), ("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
      ("&lt;", "<"), ("&gt;", ">"), ("&rsquo;", "\u{2019}"), ("&lsquo;", "\u{2018}"),
      ("&rdquo;", "\u{201D}"), ("&ldquo;", "\u{201C}"), ("&mdash;", "\u{2014}"), ("&ndash;", "\u{2013}"),
      ("&hellip;", "\u{2026}"),
    ] {
      text = text.replacingOccurrences(of: entity, with: character)
    }
    return
      text
      .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
