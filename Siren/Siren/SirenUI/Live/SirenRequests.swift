import API
import SirenKit
import SwiftUI

/// The current profile's ReadMeABook connection and requests.
@MainActor @Observable
final class SirenRequests {
  static let shared = SirenRequests()

  private(set) var client: ReadMeABook?
  private(set) var user: ReadMeABook.User?
  private(set) var requests: [ReadMeABook.Request] = []
  private var loadedProfile: String?

  private init() {}

  var isConnected: Bool { client != nil }

  /// Loads the active profile's account when the profile changed.
  func sync() {
    let profile = SirenProfiles.shared.activeID
    guard profile != loadedProfile else { return }
    loadedProfile = profile
    client = profile.flatMap(RequestsAccount.load(profileID:)).map(ReadMeABook.init(account:))
    user = nil
    requests = []
  }

  func connect(url: URL, token: String) async throws {
    guard let profile = SirenProfiles.shared.activeID else { return }
    let account = RequestsAccount(url: url, token: token)
    let client = ReadMeABook(account: account)
    let user = try await client.me()
    guard SirenProfiles.shared.activeID == profile else { return }
    self.user = user
    try account.save(profileID: profile)
    loadedProfile = profile
    self.client = client
    await refresh()
  }

  func disconnect() {
    if let profile = SirenProfiles.shared.activeID { RequestsAccount.remove(profileID: profile) }
    client = nil
    user = nil
    requests = []
  }

  func refresh() async {
    sync()
    guard let client else { return }
    let account = client.account
    // A profile switch or disconnect during the wait makes these answers someone else's.
    func isCurrent() -> Bool { self.client?.account == account && !Task.isCancelled }
    if user == nil, let me = try? await client.me(), isCurrent() { user = me }
    if let loaded = try? await client.myRequests(), isCurrent() { requests = loaded }
  }

  func request(_ book: ReadMeABook.SearchResult) async throws {
    guard let client else { return }
    try await client.request(book)
    await refresh()
  }

  /// Requests a book Audible recommended.
  func request(_ product: AudibleProduct) async throws {
    guard let client else { return }
    try await client.request(
      asin: product.asin,
      title: product.title,
      author: product.author,
      narrator: product.narrator.isEmpty ? nil : product.narrator,
      coverArtUrl: product.coverURL?.absoluteString
    )
    await refresh()
  }

  func cancel(_ request: ReadMeABook.Request) async {
    guard let client else { return }
    do {
      try await client.cancel(request)
      Toast(success: "Request canceled").show()
    } catch {
      Toast(error: error.localizedDescription).show()
    }
    await refresh()
  }

  /// Opens a ready book in the library, matched by ASIN (title as a fallback).
  static func openInLibrary(asin: String?, title: String) {
    Task {
      let books = (try? await Audiobookshelf.shared.search.search(query: title, limit: 25).book) ?? []
      let match =
        books.first { asin != nil && $0.libraryItem.media.metadata.asin == asin }
        ?? books.first { $0.libraryItem.media.metadata.title == title }
      if let match {
        SirenRouter.shared.openBook(match.libraryItem.id)
      } else {
        Toast(error: "It isn't in the library yet. Try again after the next scan.").show()
      }
    }
  }
}

extension ReadMeABook.Status {
  func label(progress: Int, releaseDate: String?) -> String {
    switch self {
    case .waitingForApproval: String(localized: "Waiting for approval")
    case .searching: String(localized: "Searching")
    case .downloading: String(localized: "Downloading \(progress)%")
    case .adding: String(localized: "Adding to library")
    case .awaitingRelease:
      releaseDate.flatMap(SirenRequestDate.short).map { String(localized: "Out \($0)") }
        ?? String(localized: "Awaiting release")
    case .available: String(localized: "Ready")
    case .failed: String(localized: "Couldn't find it")
    case .declined: String(localized: "Declined")
    case .cancelled: String(localized: "Canceled")
    case .other(let raw): raw
    }
  }
}

enum SirenRequestDate {
  /// "Mar 3" from an ISO date or datetime; nil when it can't be read.
  static func short(_ text: String) -> String? {
    date(text)?.formatted(.dateTime.month(.abbreviated).day())
  }

  static func date(_ text: String) -> Date? {
    if let date = try? Date(text, strategy: .iso8601) { return date }
    return try? Date(String(text.prefix(10)), strategy: .iso8601.year().month().day())
  }
}

/// Connect a profile to ReadMeABook with its own token.
struct SirenRequestsSettingsView: View {
  @State private var requests = SirenRequests.shared
  @ObservedObject private var authentication = Audiobookshelf.shared.authentication
  @State private var address = ""
  @State private var token = ""
  @State private var isConnecting = false
  @State private var error: String?

  var body: some View {
    Form {
      if let client = requests.client {
        Section {
          LabeledContent("Signed in as", value: requests.user?.username ?? "…")
          LabeledContent("Address", value: client.account.url.absoluteString)
          if requests.user?.isAdmin == true {
            Link(destination: client.account.url) {
              Label("Approve Requests in ReadMeABook", systemImage: "checkmark.seal")
            }
          }
        } footer: {
          Text("Search lets you request books you don't have. Home shows how each request is going.")
        }
        .listRowBackground(SirenTheme.raised)
        Section {
          Button("Disconnect", role: .destructive, action: requests.disconnect)
            .listRowBackground(SirenTheme.raised)
        }
      } else {
        Section {
          TextField("Address", text: $address, prompt: Text("http://server:3030"))
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          HStack {
            SecureField("API token", text: $token, prompt: Text("rmab_…"))
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
            PasteButton(payloadType: String.self) { strings in
              if let pasted = strings.first { token = pasted.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.capsule)
          }
        } header: {
          Text("ReadMeABook")
        } footer: {
          VStack(alignment: .leading, spacing: 6) {
            Text(
              "Make a token in ReadMeABook under Profile › API Tokens, then paste it here. Each person uses their own."
            )
            if let page = tokenPage {
              Link("Open ReadMeABook", destination: page)
            }
          }
        }
        .listRowBackground(SirenTheme.raised)

        Section {
          Button(action: connect) {
            if isConnecting {
              ProgressView().frame(maxWidth: .infinity)
            } else {
              Text("Connect").frame(maxWidth: .infinity)
            }
          }
          .disabled(isConnecting || parsedURL == nil || token.isEmpty)
          .listRowBackground(SirenTheme.raised)
        }

        if let error {
          Section {
            Label(error, systemImage: "exclamationmark.triangle")
              .foregroundStyle(SirenTheme.ink)
              .listRowBackground(SirenTheme.raised)
          }
        }
      }
    }
    .scrollContentBackground(.hidden)
    .background(SirenTheme.ground)
    .navigationTitle("Book Requests")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      requests.sync()
      if address.isEmpty, let server = authentication.server?.baseURL,
        let suggested = ReadMeABook.suggestedURL(near: server)
      {
        address = suggested.absoluteString
      }
    }
  }

  private var parsedURL: URL? {
    let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed), url.scheme == "http" || url.scheme == "https", url.host() != nil
    else { return nil }
    return url
  }

  private var tokenPage: URL? { parsedURL?.appending(path: "profile") }

  private func connect() {
    guard let url = parsedURL else { return }
    isConnecting = true
    error = nil
    Task {
      defer { isConnecting = false }
      do {
        try await requests.connect(url: url, token: token.trimmingCharacters(in: .whitespacesAndNewlines))
        token = ""
      } catch {
        self.error = "Couldn't connect. \(error.localizedDescription)"
      }
    }
  }
}

/// Home's Requests: what's on its way, then what just arrived. Polls while Home is on screen and
/// something is still on its way.
struct SirenRequestsShelf: View {
  var refreshID: Int
  @State private var requests = SirenRequests.shared

  /// On its way, then the three most recently ready, then anything that failed or was declined
  /// in the last two weeks, so a request never just disappears.
  private var shown: [ReadMeABook.Request] {
    let all = requests.requests
    let active = all.filter { $0.status.isActive }
    let ready = all.filter { $0.status == .available }.prefix(3)  // newest change first
    let cutoff = Date.now.addingTimeInterval(-14 * 86_400)
    let unsuccessful = all.filter { request in
      (request.status == .failed || request.status == .declined)
        && ((request.updatedAt ?? request.createdAt).flatMap(SirenRequestDate.date) ?? .distantPast) > cutoff
    }
    return active + ready + unsuccessful
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if !shown.isEmpty {
        SirenHomeSection(title: "Requests") {
          VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, request in
              row(request)
              if index < shown.count - 1 {
                Divider().padding(.leading, 68)
              }
            }
          }
          .background(SirenTheme.raised, in: RoundedRectangle(cornerRadius: SirenTheme.rowRadius, style: .continuous))
        }
      }
    }
    // Also restarts when a request starts elsewhere (a recommendation), so its progress shows.
    .task(id: Poll(refreshID: refreshID, isActive: requests.requests.contains { $0.status.isActive })) {
      while !Task.isCancelled {
        await requests.refresh()
        guard requests.requests.contains(where: { $0.status.isActive }) else { return }
        try? await Task.sleep(for: .seconds(30))
      }
    }
  }

  private struct Poll: Hashable {
    let refreshID: Int
    let isActive: Bool
  }

  private func row(_ request: ReadMeABook.Request) -> some View {
    let book = SirenBook(
      id: request.id,
      title: request.audiobook.title,
      author: request.audiobook.author,
      coverURL: request.audiobook.coverURL
    )
    let label = request.status.label(progress: request.progress, releaseDate: request.releaseDate)
    return Button {
      if request.status == .available {
        SirenRequests.openInLibrary(asin: request.audiobook.audibleAsin, title: request.audiobook.title)
      }
    } label: {
      HStack(spacing: 12) {
        RevealCover(book: book, progress: 0, cornerRadius: 4, shadow: false)
          .frame(width: 44, height: 44)
        VStack(alignment: .leading, spacing: 3) {
          Text(book.title)
            .font(SirenType.bookTitle(.headline))
            .foregroundStyle(SirenTheme.ink)
            .lineLimit(1)
          HStack(spacing: 8) {
            Text(label)
              .font(.footnote)
              .foregroundStyle(request.status == .downloading ? SirenTheme.tint : SirenTheme.secondary)
              .monospacedDigit()
            if request.status == .downloading {
              ProgressView(value: Double(request.progress), total: 100)
                .frame(width: 44)
                .tint(SirenTheme.tint)
                .accessibilityHidden(true)
            }
          }
        }
        Spacer(minLength: 8)
        if request.status == .available {
          Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(SirenTheme.secondary)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 10)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .contextMenu {
      if request.status.canCancel {
        Button("Cancel Request", systemImage: "xmark.circle", role: .destructive) {
          Task { await requests.cancel(request) }
        }
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityHint(request.status == .available ? "Opens the book" : "")
  }
}

/// A catalog result in Search's Request scope.
struct SirenRequestResultRow: View {
  let result: ReadMeABook.SearchResult
  @State private var requests = SirenRequests.shared
  @State private var isRequesting = false

  private var book: SirenBook {
    var book = SirenBook(id: result.asin, title: result.title, author: result.author, coverURL: result.coverURL)
    book.inLibrary = result.isAvailable
    return book
  }

  private var releaseDate: Date? {
    result.releaseDate.flatMap(SirenRequestDate.date).flatMap { $0 > .now ? $0 : nil }
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      RevealCover(book: book, progress: 0, cornerRadius: 4, shadow: false)
        .frame(width: 56, height: 56)
      VStack(alignment: .leading, spacing: 3) {
        Text(result.title)
          .font(SirenType.bookTitle(.body))
          .foregroundStyle(SirenTheme.ink)
        Text(byline)
          .font(.subheadline)
          .foregroundStyle(SirenTheme.secondary)
        if (result.rating ?? 0) > 0 || result.durationMinutes != nil {
          HStack(spacing: 8) {
            if let rating = result.rating, rating > 0 {
              StarRating(rating: rating, count: 0, compact: true)
            }
            if let minutes = result.durationMinutes {
              Text(SirenFormat.span(minutes * 60))
                .font(.footnote)
                .foregroundStyle(SirenTheme.secondary)
                .monospacedDigit()
            }
          }
          .padding(.top, 2)
        }
        control
          .fixedSize()
          .padding(.top, 6)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 6)
  }

  /// Your request for this book, from the list Home keeps fresh.
  private var myRequest: ReadMeABook.Request? {
    requests.requests.first { $0.audiobook.audibleAsin == result.asin }
  }

  /// Where the book's request stands: yours if listed, else what the search reported. Failed and
  /// canceled ones can be requested again.
  private var currentStatus: ReadMeABook.Status? {
    if let myRequest { return myRequest.status }
    guard result.isRequested else { return nil }
    return result.requestStatus.map(ReadMeABook.Status.init) ?? .searching
  }

  private var byline: String {
    guard let series = result.series else { return result.author }
    guard let part = result.seriesPart else { return "\(result.author) · \(series)" }
    return "\(result.author) · \(series), Book \(part)"
  }

  @ViewBuilder private var control: some View {
    if result.isAvailable {
      Button("In Library") { SirenRequests.openInLibrary(asin: result.asin, title: result.title) }
        .buttonStyle(RequestSearchCapsuleStyle(filled: false))
        .accessibilityLabel("Open \(result.title) in your library")
    } else if let status = currentStatus, !status.canRequestAgain {
      Label(status.label(progress: myRequest?.progress ?? 0, releaseDate: result.releaseDate), systemImage: "checkmark")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(SirenTheme.secondary)
    } else {
      VStack(alignment: .leading, spacing: 2) {
        Button(action: request) {
          if isRequesting {
            ProgressView()
          } else {
            Text("Request")
          }
        }
        .buttonStyle(RequestSearchCapsuleStyle(filled: releaseDate == nil))
        .disabled(isRequesting)
        .accessibilityLabel("Request \(result.title)")
        if let releaseDate {
          Text("Out \(releaseDate.formatted(.dateTime.month(.abbreviated).day()))")
            .font(.caption)
            .foregroundStyle(SirenTheme.secondary)
        }
      }
    }
  }

  private func request() {
    isRequesting = true
    Task {
      defer { isRequesting = false }
      do {
        try await requests.request(result)
      } catch let failure as ReadMeABook.Failure where failure.status == 409 {
        Toast(message: failure.localizedDescription).show()
        await requests.refresh()
      } catch {
        Toast(error: error.localizedDescription).show()
      }
    }
  }
}
