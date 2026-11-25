import API
import Models
import SwiftUI

/// Home bound to upstream's `HomePageModel`: Continue Listening, the yearly goal, then the
/// server's shelves in the order set in Settings › Home.
struct SirenLiveHome: View {
  @StateObject private var model: HomePage.Model = HomePageModel()
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

  private struct YearGoal {
    var finished: [SirenBook]
    var booksFinished: Int
    var hoursListened: Int
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        if authentication.server?.status == .authenticationError {
          signedOutBanner
        }
        if let error = model.error {
          Text(error)
            .font(.subheadline)
            .foregroundStyle(SirenTheme.ink)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: SirenTheme.rowRadius))
        }

        if sizeClass == .regular {
          HStack(alignment: .top, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) { continueSection }
              .frame(maxWidth: .infinity, alignment: .leading)
            if showGoal, year != nil {
              VStack(alignment: .leading, spacing: 14) {
                SirenSectionHeader(title: "Your \(String(Calendar.current.component(.year, from: .now)))")
                goalCard
              }
              .frame(maxWidth: 460)
            }
          }
        } else {
          continueSection
          goalCard
        }

        SirenRequestsShelf(refreshID: sentRefresh)

        if let username = authentication.server?.username, let libraryID = libraries.current?.id {
          SirenSentShelf(username: username, libraryID: libraryID, refreshID: sentRefresh) { open($0.id) }
            .id("\(libraryID)/\(username)")
        }

        ForEach(model.sections, id: \.id) { section in
          shelf(section)
        }
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 32)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(SirenTheme.ground)
    .navigationTitle("Home")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) { profileMenu }
    }
    .refreshable {
      sentRefresh += 1
      await model.refresh()
      await loadYear()
    }
    .onAppear {
      model.onAppear()
      sentRefresh += 1
    }
    .task(id: libraries.current?.id) { await loadYear() }
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

  @ViewBuilder private var continueSection: some View {
    if let hero {
      SirenSectionHeader(title: "Continue Listening")
      SirenContinueCard(
        book: hero,
        isPlaying: isPlaying(hero.id),
        onOpen: { open(hero.id) },
        onResume: { resume(hero.id) }
      )
    } else if !model.isLoading, libraries.current != nil {
      emptyState
    }
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

  private var continueItems: [BookCard.Model] {
    for section in model.sections {
      if case .continueBooks(let items) = section.items { return items.items }
    }
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
    case .continueBooks(let items) where items.items.count > 1:
      SirenSectionHeader(title: "Also Listening")
      SirenCoverShelf(books: items.items.dropFirst().map(SirenBook.init(card:))) { open($0.id) }
    case .books(let items) where !items.isEmpty:
      SirenSectionHeader(title: section.title)
      SirenCoverShelf(books: items.map(SirenBook.init(card:))) { open($0.id) }
    case .playlist(_, let items):
      let books = items.compactMap { item -> SirenBook? in
        if case .book(let card) = item { return SirenBook(card: card) }
        return nil
      }
      if !books.isEmpty {
        SirenSectionHeader(title: section.title)
        SirenCoverShelf(books: books) { open($0.id) }
      }
    case .series(let items) where !items.isEmpty:
      SirenSectionHeader(title: section.title)
      SirenCoverShelf(books: items.map(SirenBook.init(series:))) { book in
        guard let libraryID = libraries.current?.id else { return }
        router.homePath.append(NavigationDestination.series(id: book.id, name: book.title, libraryID: libraryID))
      }
    case .authors(let items) where !items.isEmpty:
      SirenSectionHeader(title: section.title)
      authorRow(items)
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
