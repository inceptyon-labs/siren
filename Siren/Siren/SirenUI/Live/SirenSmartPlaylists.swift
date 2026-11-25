import API
import SirenKit
import SwiftUI

/// Library's Playlists scope: your smart playlists, then the server's playlists.
struct SirenPlaylistsList: View {
  @State private var smart = SmartPlaylists.shared
  @State private var server: [Playlist] = []
  @State private var isLoading = true
  @State private var creating: SmartPlaylist?

  var body: some View {
    List {
      Section {
        ForEach(smart.all) { playlist in
          NavigationLink(value: SirenRoute.smartPlaylist(playlist.id)) {
            VStack(alignment: .leading, spacing: 2) {
              Label(playlist.name, systemImage: "wand.and.stars")
                .foregroundStyle(SirenTheme.ink)
              Text(playlist.summary)
                .font(.footnote)
                .foregroundStyle(SirenTheme.secondary)
                .lineLimit(2)
                .padding(.leading, 34)
            }
            .padding(.vertical, 2)
          }
          .listRowBackground(SirenTheme.raised)
        }
        Button {
          creating = SmartPlaylist(name: "")
        } label: {
          Label("New Smart Playlist", systemImage: "plus")
        }
        .listRowBackground(SirenTheme.raised)
      } header: {
        Text("Smart Playlists")
      } footer: {
        Text("Books that match rules you set, kept up to date as the library changes. Synced through iCloud.")
      }

      if !server.isEmpty {
        Section("Playlists") {
          ForEach(server, id: \.id) { playlist in
            NavigationLink(value: NavigationDestination.playlist(id: playlist.id)) {
              LabeledContent {
                Text(playlist.items.count, format: .number)
                  .monospacedDigit()
              } label: {
                Label(playlist.name, systemImage: "music.note.list")
                  .foregroundStyle(SirenTheme.ink)
              }
            }
            .listRowBackground(SirenTheme.raised)
          }
        }
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(SirenTheme.ground)
    .task { await loadServer() }
    .refreshable { await loadServer() }
    .sheet(item: $creating) { playlist in
      SirenSmartPlaylistEditor(playlist: playlist, isNew: true)
    }
  }

  private func loadServer() async {
    defer { isLoading = false }
    if let playlists = try? await Audiobookshelf.shared.playlists.fetch().results {
      server = playlists
    }
  }
}

/// A smart playlist's books.
struct SirenSmartPlaylistView: View {
  let id: UUID
  @State private var store = SmartPlaylists.shared
  @ObservedObject private var pinned = PinnedPlaylistManager.shared
  @Environment(\.dismiss) private var dismiss

  @State private var found: [Book] = []
  @State private var isLoading = true
  @State private var error: String?
  @State private var editing: SmartPlaylist?
  @State private var confirmsDelete = false
  @State private var isSaving = false
  /// Bumped by every load, so an older one (a refresh, say) can't land over a newer one.
  @State private var generation = 0

  private static let columns = [GridItem(.adaptive(minimum: 100, maximum: 170), spacing: 14, alignment: .top)]

  var body: some View {
    if let playlist = store.playlist(id) {
      content(playlist)
    } else {
      ContentUnavailableView("Playlist Deleted", systemImage: "wand.and.stars")
        .background(SirenTheme.ground)
    }
  }

  private func content(_ playlist: SmartPlaylist) -> some View {
    ScrollView {
      Text(playlist.summary)
        .font(.subheadline)
        .foregroundStyle(SirenTheme.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
      LazyVGrid(columns: Self.columns, alignment: .leading, spacing: 22) {
        ForEach(found, id: \.id) { item in
          NavigationLink(value: NavigationDestination.book(id: item.id)) {
            SirenLibraryCell(book: book(item), showsRating: playlist.usesRatings)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 20)
    }
    .background(SirenTheme.ground)
    .overlay {
      if found.isEmpty {
        if isLoading {
          ProgressView()
        } else if let error {
          ContentUnavailableView("Couldn't Load", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
          ContentUnavailableView(
            "No Books",
            systemImage: "wand.and.stars",
            description: Text("Nothing in this library matches these rules yet.")
          )
        }
      }
    }
    .navigationTitle(playlist.name)
    .navigationBarTitleDisplayMode(.large)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button("Edit") { editing = playlist }
        menu(playlist)
      }
    }
    .task(id: playlist) { await load(playlist) }
    .refreshable { await load(playlist) }
    .sheet(item: $editing) { playlist in
      SirenSmartPlaylistEditor(playlist: playlist, isNew: false)
    }
    .confirmationDialog("Delete \(playlist.name)?", isPresented: $confirmsDelete, titleVisibility: .visible) {
      Button("Delete Smart Playlist", role: .destructive) {
        store.forgetServerCopy(playlist.id)
        store.delete(playlist.id)
        dismiss()
      }
    } message: {
      Text(
        store.savedPlaylistID(playlist.id) == nil
          ? "This deletes it on all your devices."
          : "This deletes it on all your devices. Its copy on Audiobookshelf stays, but stops updating."
      )
    }
  }

  private func menu(_ playlist: SmartPlaylist) -> some View {
    Menu {
      let savedID = store.savedPlaylistID(playlist.id)
      Section {
        Button(
          savedID == nil ? "Save to Audiobookshelf" : "Update on Audiobookshelf",
          systemImage: "square.and.arrow.up"
        ) { save(playlist, pin: false) }
        if let savedID, pinned.isPinned(savedID) {
          Button("Unpin from Home", systemImage: "pin.slash") { pinned.unpin() }
        } else {
          Button("Pin to Home", systemImage: "pin") { save(playlist, pin: true) }
        }
      } footer: {
        Text("Saving keeps a copy on the server for other apps; Siren keeps it up to date.")
      }
      Button("Delete…", systemImage: "trash", role: .destructive) { confirmsDelete = true }
    } label: {
      if isSaving {
        ProgressView()
      } else {
        Label("More", systemImage: "ellipsis")
      }
    }
    .disabled(isSaving)
  }

  private func book(_ item: Book) -> SirenBook {
    var book = SirenBook(book: item)
    book.apply(AudibleRatings.shared.rating(for: item.media.metadata.asin))
    return book
  }

  private func load(_ playlist: SmartPlaylist) async {
    generation += 1
    let current = generation
    isLoading = true
    do {
      let books = try await store.books(for: playlist)
      guard generation == current else { return }
      found = books
      error = nil
    } catch {
      guard generation == current else { return }
      self.error = error.localizedDescription
    }
    isLoading = false
  }

  private func save(_ playlist: SmartPlaylist, pin: Bool) {
    isSaving = true
    Task {
      defer { isSaving = false }
      do {
        let savedID = try await store.saveToServer(playlist)
        if pin {
          pinned.pin(savedID)
          Toast(success: "Pinned to Home").show()
        } else {
          Toast(success: "Saved to Audiobookshelf").show()
        }
      } catch {
        Toast(error: error.localizedDescription).show()
      }
    }
  }
}

// MARK: Editor

/// Makes or edits a smart playlist: a name, rules every book must match, and an order.
struct SirenSmartPlaylistEditor: View {
  let isNew: Bool
  @Environment(\.dismiss) private var dismiss
  @State private var draft: SmartPlaylist
  @State private var rules: [EditableRule]
  @State private var options: FilterData?

  /// Rules don't have identities of their own; the list needs them.
  private struct EditableRule: Identifiable {
    let id = UUID()
    var rule: SmartPlaylist.Rule
  }

  init(playlist: SmartPlaylist, isNew: Bool) {
    self.isNew = isNew
    _draft = State(initialValue: playlist)
    _rules = State(initialValue: playlist.rules.map { EditableRule(rule: $0) })
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $draft.name)
        }
        Section {
          ForEach($rules) { $rule in
            SirenRuleRow(rule: $rule.rule, options: options)
          }
          .onDelete { rules.remove(atOffsets: $0) }
          addRuleMenu
        } header: {
          Text("Rules")
        } footer: {
          Text(rules.isEmpty ? "With no rules, every book is in it." : "A book is in it when it matches every rule.")
        }
        Section("Order") {
          Picker("Sort By", selection: $draft.sort) {
            ForEach(SmartPlaylist.Sort.allCases, id: \.self) { sort in
              Text(sort.title).tag(sort)
            }
          }
          Picker("Show", selection: $draft.limit) {
            Text("All Books").tag(Int?.none)
            ForEach([10, 25, 50, 100], id: \.self) { count in
              Text("First \(count)").tag(Int?.some(count))
            }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(SirenTheme.ground)
      .navigationTitle(isNew ? "New Smart Playlist" : "Edit Smart Playlist")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(isNew ? "Create" : "Save") {
            draft.name = draft.name.trimmingCharacters(in: .whitespaces)
            draft.rules = rules.map(\.rule)
            SmartPlaylists.shared.save(draft)
            dismiss()
          }
          .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || rules.contains { $0.rule.isBlank })
        }
      }
      .task {
        options = Audiobookshelf.shared.filterData.cached()
        if let fresh = try? await Audiobookshelf.shared.filterData.fetch() { options = fresh }
      }
    }
    .tint(SirenTheme.tint)
  }

  private var addRuleMenu: some View {
    Menu {
      Section {
        add("Genre", .genre(name: options?.genres.first ?? ""))
        add("Tag", .tag(name: options?.tags.first ?? ""))
        add("Author", .author(name: options?.authors.first?.name ?? ""))
        add("Narrator", .narrator(name: options?.narrators.first ?? ""))
        add("Series", .series(name: options?.series.first?.name ?? ""))
      }
      Section {
        add("Progress", .progress(.notStarted))
        add("Length", .length(atLeast: 5, atMost: nil))
        add("Audible Rating", .rating(atLeast: 4.5))
        add("Added Recently", .addedWithin(days: 30))
        add("Language", .language(name: options?.languages.first ?? "English"))
        add("Explicit", .explicit(false))
      }
    } label: {
      Label("Add Rule", systemImage: "plus.circle")
    }
  }

  private func add(_ title: LocalizedStringKey, _ rule: SmartPlaylist.Rule) -> some View {
    Button(title) { rules.append(EditableRule(rule: rule)) }
  }
}

/// One rule, edited in place.
private struct SirenRuleRow: View {
  @Binding var rule: SmartPlaylist.Rule
  let options: FilterData?

  var body: some View {
    switch rule {
    case .genre(let name):
      names("Genre", name, options?.genres) { rule = .genre(name: $0) }
    case .tag(let name):
      names("Tag", name, options?.tags) { rule = .tag(name: $0) }
    case .author(let name):
      names("Author", name, options?.authors.map(\.name)) { rule = .author(name: $0) }
    case .narrator(let name):
      names("Narrator", name, options?.narrators) { rule = .narrator(name: $0) }
    case .series(let name):
      names("Series", name, options?.series.map(\.name)) { rule = .series(name: $0) }
    case .language(let name):
      names("Language", name, options?.languages) { rule = .language(name: $0) }
    case .progress(let state):
      Picker("Progress", selection: Binding(get: { state }, set: { rule = .progress($0) })) {
        Text("Not started").tag(SmartPlaylist.Progress.notStarted)
        Text("In progress").tag(SmartPlaylist.Progress.inProgress)
        Text("Finished").tag(SmartPlaylist.Progress.finished)
      }
    case .length(let atLeast, let atMost):
      let current = LengthRange(atLeast: atLeast, atMost: atMost)
      Picker(
        "Length",
        selection: Binding(get: { current }, set: { rule = .length(atLeast: $0.atLeast, atMost: $0.atMost) })
      ) {
        if !LengthRange.presets.contains(current) {
          Text(rule.summary).tag(current)
        }
        ForEach(LengthRange.presets, id: \.self) { range in
          Text(SmartPlaylist.Rule.length(atLeast: range.atLeast, atMost: range.atMost).summary).tag(range)
        }
      }
    case .rating(let atLeast):
      Picker("Audible Rating", selection: Binding(get: { atLeast }, set: { rule = .rating(atLeast: $0) })) {
        ForEach([3.5, 4.0, 4.5], id: \.self) { stars in
          Text("\(stars.formatted(.number.precision(.fractionLength(1)))) stars and up").tag(stars)
        }
      }
    case .addedWithin(let days):
      Picker("Added", selection: Binding(get: { days }, set: { rule = .addedWithin(days: $0) })) {
        Text("In the last week").tag(7)
        Text("In the last month").tag(30)
        Text("In the last 3 months").tag(90)
        Text("In the last year").tag(365)
      }
    case .explicit(let isExplicit):
      Picker("Explicit", selection: Binding(get: { isExplicit }, set: { rule = .explicit($0) })) {
        Text("Not explicit").tag(false)
        Text("Explicit only").tag(true)
      }
    }
  }

  /// A rule naming a genre, tag, person, series or language: picked from the library's own,
  /// or typed when the library's list hasn't loaded.
  @ViewBuilder private func names(
    _ title: LocalizedStringKey,
    _ name: String,
    _ choices: [String]?,
    set: @escaping (String) -> Void
  ) -> some View {
    let binding = Binding(get: { name }, set: set)
    if let choices, !choices.isEmpty {
      Picker(title, selection: binding) {
        // Keep a saved name the library no longer has, so the picker shows it.
        if !choices.contains(name) {
          Text(name.isEmpty ? String(localized: "Choose") : name).tag(name)
        }
        ForEach(choices, id: \.self) { Text($0).tag($0) }
      }
      .pickerStyle(.navigationLink)
    } else {
      LabeledContent(title) {
        TextField(title, text: binding)
          .multilineTextAlignment(.trailing)
      }
    }
  }

  private struct LengthRange: Hashable {
    let atLeast: Double?
    let atMost: Double?

    static let presets = [
      LengthRange(atLeast: nil, atMost: 3),
      LengthRange(atLeast: nil, atMost: 5),
      LengthRange(atLeast: 5, atMost: 10),
      LengthRange(atLeast: 10, atMost: 20),
      LengthRange(atLeast: 5, atMost: nil),
      LengthRange(atLeast: 10, atMost: nil),
      LengthRange(atLeast: 20, atMost: nil),
    ]
  }
}

// MARK: Words

extension SmartPlaylist {
  /// Its rules in a line: "Fantasy · Not started · Rated 4.5+".
  var summary: String {
    guard !rules.isEmpty else { return String(localized: "Every book") }
    return rules.map(\.summary).joined(separator: " · ")
  }
}

extension SmartPlaylist.Rule {
  /// A name rule with no name yet: it would match nothing.
  var isBlank: Bool {
    switch self {
    case .genre(let name), .tag(let name), .author(let name), .narrator(let name), .series(let name),
      .language(let name):
      name.trimmingCharacters(in: .whitespaces).isEmpty
    default: false
    }
  }

  var summary: String {
    switch self {
    case .genre(let name), .tag(let name): return name
    case .author(let name): return String(localized: "By \(name)")
    case .narrator(let name): return String(localized: "Read by \(name)")
    case .series(let name): return String(localized: "In \(name)")
    case .language(let name): return name
    case .progress(.notStarted): return String(localized: "Not started")
    case .progress(.inProgress): return String(localized: "In progress")
    case .progress(.finished): return String(localized: "Finished")
    case .length(let atLeast?, let atMost?): return String(localized: "\(Int(atLeast))–\(Int(atMost)) hours")
    case .length(let atLeast?, nil): return String(localized: "Over \(Int(atLeast)) hours")
    case .length(nil, let atMost?): return String(localized: "Under \(Int(atMost)) hours")
    case .length(nil, nil): return String(localized: "Any length")
    case .rating(let atLeast):
      return String(localized: "Rated \(atLeast.formatted(.number.precision(.fractionLength(1))))+")
    case .addedWithin(let days): return String(localized: "Added in the last \(days) days")
    case .explicit(let isExplicit):
      return isExplicit ? String(localized: "Explicit") : String(localized: "Not explicit")
    }
  }
}

extension SmartPlaylist.Sort {
  var title: LocalizedStringKey {
    switch self {
    case .recentlyAdded: "Recently Added"
    case .rating: "Audible Rating"
    case .title: "Title"
    case .shortest: "Shortest First"
    case .longest: "Longest First"
    }
  }
}
