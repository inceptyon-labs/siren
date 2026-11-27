import API
import Models
import SirenKit
import SwiftUI

/// Home bound to upstream's `HomePageModel`: Continue Listening, the yearly goal, then the
/// server's shelves in the order set in Settings › Home.
struct SirenLiveHome: View {
  @StateObject private var model: HomePage.Model
  @ObservedObject private var playerManager = PlayerManager.shared
  @ObservedObject private var authentication = Audiobookshelf.shared.authentication
  @ObservedObject private var libraries = Audiobookshelf.shared.libraries
  @ObservedObject private var preferences = UserPreferences.shared
  @Environment(\.horizontalSizeClass) private var sizeClass

  @AppStorage(SirenSettings.goalUnit) private var goalUnit: SirenGoalUnit = .books
  @AppStorage(SirenSettings.bookGoal) private var bookGoal = 20
  @AppStorage(SirenSettings.hourGoal) private var hourGoal = 150
  @AppStorage(SirenSettings.goalOnHome) private var showGoal = true

  @State private var router = SirenRouter.shared
  @State private var year: YearGoal?
  @State private var heroDetail: SirenBook?
  @State private var showingSettings = false
  @State private var showingServerList = false
  @State private var showingInvite = false
  @State private var showingAdmin = false
  @State private var sentRefresh = 0
  @State private var profiles = SirenProfiles.shared
  /// The full-width cover is under the status bar, which then needs light text.
  @State private var overCover = true

  private struct YearGoal {
    var finished: [SirenBook]
    var booksFinished: Int
    var hoursListened: Int
  }

  /// `preview` stands in for the server's shelves (the `live-home` demo screen).
  init(preview: HomePage.Model? = nil) {
    _model = StateObject(wrappedValue: preview ?? HomePageModel())
    if preview != nil {
      let finished = Array(Demo.finished2026.prefix(6))
      _year = State(initialValue: YearGoal(finished: finished, booksFinished: finished.count, hoursListened: 70))
      // Chapters come from the server for a live hero; the preview makes some up.
      if case .continueBooks(let items) = preview?.sections.first?.items, let first = items.items.first {
        var detail = SirenBook(card: first)
        detail.chapterCount = 34
        detail.chapterMarks = (0..<34).map { Double($0) / 34 }
        detail.currentChapter = 14
        detail.chapterTitle = "The Spice Harvest"
        detail.chapterRemaining = "18:42"
        _heroDetail = State(initialValue: detail)
      }
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        if bleeds, let hero {
          SirenNowHeader(
            book: hero,
            isPlaying: isPlaying(hero.id),
            onOpen: { open(hero.id) },
            onResume: { resume(hero.id) }
          )
        }
        content
      }
    }
    .ignoresSafeArea(edges: bleeds ? .top : [])
    .modifier(CoverUnderStatusBar(active: bleeds, overCover: $overCover))
    .background(SirenTheme.ground)
    .sirenHomeTitle()
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) { profileMenu }
    }
    .refreshable {
      sentRefresh += 1
      // Not awaited: a first run asks Audible about the whole library.
      Task { await SirenRecommendations.shared.refresh(force: true) }
      Task { await SmartPlaylists.shared.syncSaved(force: true) }
      await model.refresh()
      await loadYear()
    }
    .onAppear {
      model.onAppear()
      sentRefresh += 1
    }
    .task(id: libraries.current?.id) { await loadYear() }
    .task(id: libraries.current?.id) { await SirenRecommendations.shared.refresh() }
    // Saved smart playlists (and so a pinned one) follow the library.
    .task(id: libraries.current?.id) { await SmartPlaylists.shared.syncSaved() }
    .task(id: heroKey) { await loadHeroDetail() }
    .onChange(of: libraries.current) { _, new in model.onReset(new != nil) }
    .onChange(of: preferences.homeSections) { _, _ in model.onPreferencesChanged() }
    .sheet(isPresented: $showingSettings) {
      NavigationView {
        SettingsView(model: SettingsViewModel())
      }
      .displaySheetScaled()
    }
    .sheet(isPresented: $showingServerList) {
      ServerListPage(model: ServerListModel())
        .displaySheetScaled()
    }
    .sheet(isPresented: $showingInvite) {
      SirenInviteView()
    }
    .sheet(isPresented: $showingAdmin) {
      SirenServerAdminView()
    }
  }

  /// On iPhone the book you're in leads Home full width, up under the status bar.
  private var bleeds: Bool { sizeClass != .regular && hero != nil }

  private var content: some View {
    // Sections space themselves (SirenHomeSection), so an empty shelf takes no room.
    VStack(alignment: .leading, spacing: 0) {
      if authentication.server?.status == .authenticationError {
        signedOutBanner
          .padding(.bottom, 14)
      }
      if let error = model.error {
        Text(error)
          .font(.subheadline)
          .foregroundStyle(SirenTheme.ink)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: SirenTheme.rowRadius))
          .padding(.bottom, 14)
      }

      if sizeClass == .regular {
        HStack(alignment: .top, spacing: 28) {
          continueListening
            .frame(maxWidth: .infinity, alignment: .leading)
          if showGoal, year != nil {
            SirenHomeSection(title: "Your \(String(Calendar.current.component(.year, from: .now)))", divided: false) {
              goalCard
            }
            .frame(maxWidth: 460)
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 14) {
          continueListening
          goalCard
        }
      }

      SirenRequestsShelf(refreshID: sentRefresh)

      if let username = authentication.server?.username, let libraryID = libraries.current?.id {
        SirenSentShelf(username: username, libraryID: libraryID, refreshID: sentRefresh) { open($0.id) }
          .id("\(libraryID)/\(username)")
      }

      // Requests are off in a kids profile, and these are all books to request.
      if !profiles.isKidsActive {
        SirenBecauseYouLikedShelf { router.homePath.append(SirenRoute.requests) }
        SirenComingSoonShelf { router.homePath.append(SirenRoute.requests) }
      }
      SirenHighlyRatedShelf { open($0.id) }

      ForEach(model.sections, id: \.id) { section in
        shelf(section)
      }
    }
    .padding(.horizontal, 20)
    .padding(.top, bleeds ? 20 : 0)
    .padding(.bottom, 32)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// The server turned this sign-in away: a revoked invite key, or a changed password.
  private var signedOutBanner: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Signed out", systemImage: "person.crop.circle.badge.exclamationmark")
        .font(.headline)
        .foregroundStyle(SirenTheme.ink)
      Text(
        "\(authentication.server?.alias ?? "Your server") no longer accepts this sign-in. Sign in again to keep listening."
      )
      .font(.subheadline)
      .foregroundStyle(SirenTheme.secondary)
      Button("Sign In Again") { showingServerList = true }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(SirenTheme.tint)
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(SirenTheme.raised, in: RoundedRectangle(cornerRadius: SirenTheme.rowRadius))
  }

  // MARK: Continue Listening

  @ViewBuilder private var continueListening: some View {
    if bleeds {
      // The header already shows the first book.
      let others = continueItems.dropFirst().map(SirenBook.init(card:))
      if !others.isEmpty {
        SirenHomeSection(title: "Also Listening", divided: false) {
          otherRows(others)
        }
      }
    } else if let hero {
      SirenHomeSection(title: "Continue Listening", divided: false) {
        SirenContinueCard(
          book: hero,
          isPlaying: isPlaying(hero.id),
          onOpen: { open(hero.id) },
          onResume: { resume(hero.id) }
        )
        // The other books you're partway through, a tap from resuming.
        let others = continueItems.dropFirst().map(SirenBook.init(card:))
        if !others.isEmpty {
          otherRows(others)
            .padding(.top, 4)
        }
      }
    } else if !model.isLoading, libraries.current != nil {
      emptyState
    }
  }

  private func otherRows(_ books: [SirenBook]) -> some View {
    SirenBookRows(
      books: books,
      limit: 3,
      detail: { $0.timeLeft.isEmpty ? $0.author : "\($0.timeLeft) left · \($0.author)" },
      onOpen: { open($0.id) },
      onResume: { resume($0.id) }
    )
  }

  @ViewBuilder private var goalCard: some View {
    if showGoal, let year {
      SirenGoalCard(
        finished: year.finished,
        count: goalUnit == .books ? year.booksFinished : year.hoursListened,
        goal: goalUnit == .books ? bookGoal : hourGoal,
        unit: goalUnit == .books ? .books : .hours
      )
      .onTapGesture { router.homePath.append(NavigationDestination.stats) }
      .accessibilityAddTraits(.isButton)
    }
  }

  /// The first in-progress section (Continue Listening) leads Home; any later one (Continue
  /// Reading) gets its own shelf.
  private var continueSection: HomePage.Model.Section? {
    model.sections.first { section in
      if case .continueBooks = section.items { return true }
      return false
    }
  }

  private var continueItems: [BookCard.Model] {
    if case .continueBooks(let items) = continueSection?.items { return items.items }
    return []
  }

  private var heroCard: BookCard.Model? { continueItems.first }

  /// Reloads the hero's chapter position when the book or its progress changes.
  private var heroKey: String? {
    heroCard.map { "\($0.id)|\($0.cover.progress ?? 0)" }
  }

  private var hero: SirenBook? {
    guard let card = heroCard else { return nil }
    if let current = playerManager.current, current.id == card.id {
      return SirenBook(player: current)
    }
    let fresh = SirenBook(card: card)
    guard var detail = heroDetail, detail.id == card.id else { return fresh }
    // Chapters come from the fetched book; progress always from the latest card.
    detail.progress = fresh.progress
    detail.timeLeft = fresh.timeLeft
    return detail
  }

  /// Chapter position for the hero when it isn't the book in the player.
  private func loadHeroDetail() async {
    guard let card = heroCard, playerManager.current?.id != card.id else { return }
    guard let book = try? await Audiobookshelf.shared.books.fetch(id: card.id) else { return }
    let currentTime = (try? MediaProgress.fetch(bookID: card.id))?.currentTime ?? 0
    var detail = SirenBook(card: card)
    detail.apply(chapters: book.chapters ?? [], currentTime: currentTime, duration: book.duration)
    heroDetail = detail
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label("Nothing in progress", systemImage: "book")
    } description: {
      Text("Pick a book from your library to start listening.")
    } actions: {
      Button("Open Library") { router.tab = .library }
    }
    .padding(.vertical, 24)
  }

  private func isPlaying(_ id: String) -> Bool {
    guard let current = playerManager.current, current.id == id else { return false }
    return current.isPlaying
  }

  private func resume(_ id: String) {
    if let current = playerManager.current, current.id == id {
      current.onTogglePlaybackTapped()
    } else {
      Task { await playerManager.play(id) }
    }
  }

  private func open(_ id: String) {
    router.homePath.append(NavigationDestination.book(id: id))
  }

  // MARK: Yearly goal

  private func loadYear() async {
    guard libraries.current != nil else { return }
    let thisYear = Calendar.current.component(.year, from: .now)
    guard let stats = try? await authentication.fetchYearStats(year: thisYear) else { return }
    let finished = stats.finishedBooksWithCovers.map { id in
      SirenBook(id: id, title: "", author: nil, coverURL: SirenCovers.url(itemID: id))
    }
    year = YearGoal(
      finished: finished,
      booksFinished: stats.numBooksFinished,
      hoursListened: Int(stats.totalBookListeningTime / 3600)
    )
  }

  // MARK: Shelves

  @ViewBuilder private func shelf(_ section: HomePage.Model.Section) -> some View {
    switch section.items {
    case .continueBooks(let items) where section.id != continueSection?.id && !items.items.isEmpty:
      SirenHomeSection(title: section.title) {
        SirenCoverShelf(books: items.items.map(SirenBook.init(card:))) { open($0.id) }
      }
    case .books(let items) where section.id == "continue-series" && !items.isEmpty:
      // The next book in each series: which one it is matters more than its cover.
      SirenHomeSection(title: section.title) {
        SirenBookRows(
          books: items.map(SirenBook.init(card:)),
          detail: { book in book.seriesIndex.map { "Book \($0) · \(book.author)" } ?? book.author },
          onOpen: { open($0.id) }
        )
      }
    case .books(let items) where !items.isEmpty:
      SirenHomeSection(title: section.title) {
        SirenCoverShelf(books: items.map(SirenBook.init(card:))) { open($0.id) }
      }
    case .playlist(_, let items):
      let books = items.compactMap { item -> SirenBook? in
        if case .book(let card) = item { return SirenBook(card: card) }
        return nil
      }
      if !books.isEmpty {
        SirenHomeSection(title: section.title) {
          SirenCoverShelf(books: books) { open($0.id) }
        }
      }
    case .series(let items) where !items.isEmpty:
      SirenHomeSection(title: section.title) {
        SirenCoverShelf(books: items.map(SirenBook.init(series:))) { book in
          guard let libraryID = libraries.current?.id else { return }
          router.homePath.append(NavigationDestination.series(id: book.id, name: book.title, libraryID: libraryID))
        }
      }
    case .authors(let items) where !items.isEmpty:
      SirenHomeSection(title: section.title) {
        authorRow(items)
      }
    default:
      EmptyView()
    }
  }

  private func authorRow(_ authors: [AuthorCard.Model]) -> some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 10) {
        ForEach(authors, id: \.id) { author in
          Button {
            guard let libraryID = libraries.current?.id else { return }
            router.homePath.append(NavigationDestination.author(id: author.id, name: author.name, libraryID: libraryID))
          } label: {
            Text(author.name)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(SirenTheme.ink)
              .padding(.horizontal, 14)
              .frame(minHeight: 36)
              .background(SirenTheme.raised, in: Capsule())
          }
          .buttonStyle(.plain)
        }
      }
    }
    .scrollClipDisabled()
  }

  // MARK: Profile

  private var profileMenu: some View {
    Menu {
      if profiles.profiles.count > 1 {
        Section("Profiles") {
          ForEach(profiles.profiles) { profile in
            Button {
              Task { await profiles.switchTo(profile.id) }
            } label: {
              if profile.id == profiles.activeID {
                Label(profile.name, systemImage: "checkmark")
              } else {
                Text(profile.name)
              }
              Text(profile.server)
            }
          }
        }
      }
      if profiles.isKidsActive, let id = profiles.activeID {
        Section {
          Button("Leave Kids Profile…", systemImage: "lock.open") {
            Task { await profiles.setKids(false, for: id) }
          }
        }
      }
      if !profiles.isKidsActive {
        if model.availableLibraries.count > 1 {
          Picker(
            "Library",
            selection: Binding(
              get: { libraries.current?.id ?? "" },
              set: { model.onLibrarySelected($0) }
            )
          ) {
            ForEach(model.availableLibraries) { library in
              Text(library.name).tag(library.id)
            }
          }
        }
        Section {
          Button("Progress Art & Goal", systemImage: "paintbrush.pointed") {
            router.homePath.append(SirenRoute.progressArt)
          }
          Button("Listening Stats", systemImage: "chart.bar") {
            router.homePath.append(NavigationDestination.stats)
          }
          Button("Downloads", systemImage: "arrow.down.circle") {
            router.homePath.append(NavigationDestination.offline)
          }
          Button("Book Requests", systemImage: "tray.and.arrow.down") {
            router.homePath.append(SirenRoute.requests)
          }
        }
        if isAdmin {
          Section {
            Button("Invite to Siren…", systemImage: "qrcode") { showingInvite = true }
            Button("Server Admin", systemImage: "wrench.and.screwdriver") { showingAdmin = true }
          }
        }
        Section {
          Button("Servers", systemImage: "server.rack") { showingServerList = true }
          Button("Profiles…", systemImage: "person.2") { router.homePath.append(SirenRoute.profiles) }
          Button("Settings", systemImage: "gearshape") { showingSettings = true }
        }
      }
    } label: {
      Text(initial)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.white)
        .frame(width: 32, height: 32)
        .background(plate, in: Circle())
    }
    .accessibilityLabel("Profile and settings")
  }

  /// Household plates: the server admin is slate, other listeners plum, until Phase 2 lets
  /// each member pick one.
  private var plate: Color {
    isAdmin ? Color(sirenHex: 0x3B4A5C) : Color(sirenHex: 0x8E4A8C)
  }

  private var isAdmin: Bool { authentication.isSirenAdmin }

  private var initial: String {
    let name = authentication.server?.username ?? ""
    return name.first.map { String($0).uppercased() } ?? "S"
  }
}

/// Light status bar text, and no scroll edge blur, while the full-width cover is under the bar.
private struct CoverUnderStatusBar: ViewModifier {
  let active: Bool
  @Binding var overCover: Bool

  func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      tracked(content)
        .toolbarColorScheme(active && overCover ? .dark : nil, for: .navigationBar)
        .scrollEdgeEffectHidden(active && overCover, for: .top)
    } else {
      tracked(content)
        .toolbarColorScheme(active && overCover ? .dark : nil, for: .navigationBar)
    }
  }

  @ViewBuilder private func tracked(_ content: Content) -> some View {
    if #available(iOS 18.0, *) {
      content.onScrollGeometryChange(for: Bool.self) { geometry in
        // The cover is as tall as the screen is wide; past most of it, the bar is over the band.
        geometry.contentOffset.y < geometry.containerSize.width - 60
      } action: { _, isOver in
        overCover = isOver
      }
    } else {
      content
    }
  }
}
