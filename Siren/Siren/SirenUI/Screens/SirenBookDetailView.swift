import SwiftUI

/// Book detail for the design review, bound to demo data.
struct SirenBookDetailView: View {
  let book: DemoBook
  var onSend: () -> Void
  var onPlay: () -> Void

  @State private var requested: Set<String> = []

  private let coverSide: CGFloat = 220
  private let seriesCoverSide: CGFloat = 104

  var body: some View {
    ScrollView {
      VStack(spacing: 28) {
        hero
        if book.inLibrary {
          householdRow
        }
        if !seriesBooks.isEmpty {
          seriesSection
        }
        aboutSection
        detailsSection
      }
      .padding(.bottom, 32)
    }
    .modifier(BookDetailNavigationTitle(title: book.title, revealOffset: coverSide + 44))
    .background(SirenTheme.ground)
    .navigationTitle(book.title)
    .navigationBarTitleDisplayMode(.inline)
  }

  // MARK: Hero

  private var hero: some View {
    VStack(spacing: 0) {
      RevealCover(book: book, showTicks: true)
        .frame(width: coverSide, height: coverSide)
        .padding(.top, 8)

      Text(book.title)
        .font(SirenType.bookTitle(.title))
        .foregroundStyle(SirenTheme.ink)
        .multilineTextAlignment(.center)
        .padding(.top, 22)
        .accessibilityAddTraits(.isHeader)

      Text(book.author)
        .font(.body)
        .foregroundStyle(SirenTheme.ink)
        .padding(.top, 4)

      if !book.narrator.isEmpty {
        Text("Read by \(book.narrator)")
          .font(.subheadline)
          .foregroundStyle(SirenTheme.secondary)
          .padding(.top, 2)
      }

      if book.rating > 0 {
        ratings
          .padding(.top, 14)
      }

      actions
        .padding(.top, 22)
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 20)
  }

  private var ratings: some View {
    VStack(spacing: 4) {
      HStack(spacing: 4) {
        StarRating(rating: book.rating, count: book.ratingCount)
        Text("on Audible")
          .font(.footnote)
          .foregroundStyle(SirenTheme.secondary)
      }
      Text("Story \(oneDecimal(min(5, book.rating + 0.1))) · Performance \(oneDecimal(max(0, book.rating - 0.1)))")
        .font(.footnote)
        .foregroundStyle(SirenTheme.secondary)
        .monospacedDigit()
    }
    .accessibilityElement(children: .combine)
  }

  private var actions: some View {
    VStack(spacing: 12) {
      primaryAction
      if book.inLibrary {
        HStack(spacing: 12) {
          Button(action: onSend) {
            Label("Send…", systemImage: "paperplane")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(BookDetailCapsuleStyle(kind: .wash))

          Button {
          } label: {
            Image(systemName: "arrow.down.circle")
          }
          .buttonStyle(BookDetailCapsuleStyle(kind: .wash))
          .accessibilityLabel("Download")

          Button {
          } label: {
            Image(systemName: "bookmark")
          }
          .buttonStyle(BookDetailCapsuleStyle(kind: .wash))
          .accessibilityLabel("Bookmark")
        }
      }
    }
  }

  @ViewBuilder private var primaryAction: some View {
    switch shelfState(of: book) {
    case .finished, .playing, .notStarted:
      Button(action: onPlay) {
        Label(playTitle, systemImage: "play.fill")
          .monospacedDigit()
          .frame(maxWidth: .infinity)
          .padding(.horizontal, 16)
      }
      .buttonStyle(BookDetailCapsuleStyle(kind: .filled))
    case .downloading(let fraction):
      VStack(spacing: 8) {
        Text(DemoRequestStatus.downloading(fraction).label)
          .font(.headline)
          .foregroundStyle(SirenTheme.tint)
          .monospacedDigit()
        ProgressView(value: fraction)
          .tint(SirenTheme.tint)
          .accessibilityHidden(true)
      }
      .frame(minHeight: 50)
    case .pending(let status):
      Text(status.label)
        .font(.headline)
        .foregroundStyle(SirenTheme.secondary)
        .frame(minHeight: 50)
    case .requested:
      Label("Requested", systemImage: "checkmark")
        .font(.headline)
        .foregroundStyle(SirenTheme.secondary)
        .frame(minHeight: 50)
    case .requestable(let releaseDate):
      VStack(spacing: 6) {
        Button {
          requested.insert(book.id)
        } label: {
          Text("Request")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BookDetailCapsuleStyle(kind: .filled))
        if let releaseDate {
          Text("Out \(releaseDate)")
            .font(.footnote)
            .foregroundStyle(SirenTheme.secondary)
        }
      }
    }
  }

  private var playTitle: String {
    if book.isFinished { return "Listen Again" }
    if book.isStarted {
      return "Resume · Ch \(book.currentChapter) · \(book.chapterRemaining) left"
    }
    return "Play"
  }

  // MARK: Household

  private var householdRow: some View {
    HStack(spacing: 12) {
      HouseholdPlate(member: Demo.sarah, size: 32)
        .accessibilityHidden(true)
      Text("\(Demo.sarah.name) hasn't started it")
        .font(.body)
        .foregroundStyle(SirenTheme.ink)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(minHeight: 56)
    .background(SirenTheme.raised, in: RoundedRectangle(cornerRadius: SirenTheme.rowRadius, style: .continuous))
    .padding(.horizontal, 20)
    .accessibilityElement(children: .combine)
  }

  // MARK: Series

  private var seriesBooks: [DemoBook] {
    guard let series = book.series else { return [] }
    return Demo.tidewater
      .filter { $0.series == series }
      .sorted { ($0.seriesIndex ?? 0) < ($1.seriesIndex ?? 0) }
  }

  private var seriesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      SirenSectionHeader(title: book.series ?? "")
        .padding(.horizontal, 20)
      ScrollView(.horizontal) {
        HStack(alignment: .top, spacing: 14) {
          ForEach(seriesBooks) { item in
            seriesItem(item)
          }
        }
        .scrollTargetLayout()
      }
      .scrollIndicators(.hidden)
      .scrollTargetBehavior(.viewAligned)
      .contentMargins(.horizontal, 20, for: .scrollContent)
    }
  }

  private func seriesItem(_ item: DemoBook) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      if item.id == book.id {
        seriesTile(item)
      } else {
        NavigationLink(value: SirenRoute.book(item.id)) {
          seriesTile(item)
        }
        .buttonStyle(.plain)
      }
      seriesStatus(item)
    }
    .frame(width: seriesCoverSide, alignment: .leading)
  }

  private func seriesTile(_ item: DemoBook) -> some View {
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

  @ViewBuilder private func seriesStatus(_ item: DemoBook) -> some View {
    switch shelfState(of: item) {
    case .finished(let date):
      caption(date.map { "Finished \($0)" } ?? "Finished")
    case .playing(let progress):
      caption("Playing · \(percent(progress))", emphasized: true)
    case .notStarted:
      caption("Not started")
    case .downloading(let fraction):
      VStack(alignment: .leading, spacing: 5) {
        Text(DemoRequestStatus.downloading(fraction).label)
          .font(.caption.weight(.semibold))
          .foregroundStyle(SirenTheme.tint)
          .monospacedDigit()
        ProgressView(value: fraction)
          .tint(SirenTheme.tint)
          .accessibilityHidden(true)
      }
    case .pending(let status):
      caption(status.label)
    case .requested:
      Label("Requested", systemImage: "checkmark")
        .font(.caption.weight(.semibold))
        .foregroundStyle(SirenTheme.secondary)
    case .requestable(let releaseDate):
      VStack(alignment: .leading, spacing: 0) {
        if let releaseDate {
          caption("Out \(releaseDate)")
        }
        Button("Request") {
          requested.insert(item.id)
        }
        .buttonStyle(BookDetailCapsuleStyle(kind: releaseDate == nil ? .filled : .wash, compact: true))
        .accessibilityLabel("Request \(item.title)")
      }
    }
  }

  private func caption(_ text: String, emphasized: Bool = false) -> some View {
    Text(text)
      .font(emphasized ? Font.caption.weight(.semibold) : Font.caption)
      .foregroundStyle(emphasized ? SirenTheme.ink : SirenTheme.secondary)
      .monospacedDigit()
      .fixedSize(horizontal: false, vertical: true)
  }

  // MARK: About and details

  private var aboutSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      SirenSectionHeader(title: "About")
      Text(book.detailBlurb)
        .font(.body)
        .foregroundStyle(SirenTheme.ink)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 20)
  }

  private var detailsSection: some View {
    let rows = detailRows
    return VStack(alignment: .leading, spacing: 8) {
      SirenSectionHeader(title: "Details")
        .padding(.horizontal, 20)
      VStack(spacing: 0) {
        ForEach(rows) { row in
          if row.id != rows.first?.id {
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

  private struct DetailRow: Identifiable {
    let label: String
    let value: String
    var id: String { label }
  }

  private var detailRows: [DetailRow] {
    var rows: [DetailRow] = []
    if book.hours > 0 {
      rows.append(DetailRow(label: "Length", value: lengthText(book.hours)))
    }
    if book.chapterCount > 1 {
      rows.append(DetailRow(label: "Chapters", value: "\(book.chapterCount)"))
    }
    rows.append(DetailRow(label: "Genre", value: book.genre))
    if let added = book.detailAddedOn {
      rows.append(DetailRow(label: "Added", value: added))
    }
    if let release = book.releaseDate {
      rows.append(DetailRow(label: "Release", value: release))
    }
    return rows
  }

  // MARK: State

  /// One vocabulary for where a book stands, shared by the hero and the series shelf.
  private enum ShelfState {
    case finished(String?)
    case playing(Double)
    case notStarted
    case downloading(Double)
    case pending(DemoRequestStatus)
    case requested
    case requestable(releaseDate: String?)
  }

  private func shelfState(of item: DemoBook) -> ShelfState {
    if item.inLibrary {
      if item.isFinished { return .finished(item.finishedOn) }
      if item.isStarted { return .playing(item.progress) }
      return .notStarted
    }
    if requested.contains(item.id) { return .requested }
    if let request = item.request {
      if case .downloading(let fraction) = request { return .downloading(fraction) }
      return .pending(request)
    }
    return .requestable(releaseDate: item.releaseDate)
  }

  private func percent(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
  }

  private func oneDecimal(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(1)))
  }

  private func lengthText(_ hours: Double) -> String {
    let minutes = Int((hours * 60).rounded())
    return "\(minutes / 60)h \(minutes % 60)m"
  }
}

/// Shows the book title in the navigation bar only once the hero title has scrolled under it.
private struct BookDetailNavigationTitle: ViewModifier {
  let title: String
  let revealOffset: CGFloat

  @State private var revealed = false

  @ViewBuilder func body(content: Content) -> some View {
    if #available(iOS 26.0, *) {
      tracked(content)
        .toolbar {
          ToolbarItem(placement: .principal) { titleView }
            .sharedBackgroundVisibility(.hidden)
        }
    } else {
      tracked(content)
        .toolbar {
          ToolbarItem(placement: .principal) { titleView }
        }
    }
  }

  @ViewBuilder private func tracked(_ content: Content) -> some View {
    if #available(iOS 18.0, *) {
      content.onScrollGeometryChange(for: Bool.self) { geometry in
        geometry.contentOffset.y + geometry.contentInsets.top > revealOffset
      } action: { _, isPast in
        revealed = isPast
      }
    } else {
      content.onAppear { revealed = true }
    }
  }

  private var titleView: some View {
    Text(title)
      .font(SirenType.bookTitle(.headline))
      .foregroundStyle(SirenTheme.ink)
      .lineLimit(1)
      .opacity(revealed ? 1 : 0)
      .animation(.easeOut(duration: 0.2), value: revealed)
      .accessibilityHidden(!revealed)
  }
}

private struct BookDetailCapsuleStyle: ButtonStyle {
  enum Kind { case filled, wash }

  var kind: Kind
  /// Compact capsules draw 30pt tall but keep a 44pt hit area.
  var compact = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(compact ? Font.subheadline.weight(.semibold) : Font.body.weight(.semibold))
      .foregroundStyle(kind == .filled ? SirenTheme.onTint : SirenTheme.tint)
      .padding(.horizontal, compact ? 14 : 0)
      .frame(minWidth: compact ? nil : 50, minHeight: compact ? 30 : 50)
      .background(kind == .filled ? SirenTheme.tint : SirenTheme.tintWash, in: Capsule())
      .padding(.vertical, compact ? 7 : 0)
      .contentShape(Rectangle())
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}

private extension DemoBook {
  /// Synthetic jacket copy for the demo books.
  var detailBlurb: String {
    switch id {
    case Demo.saltRoad.id:
      "Twice a month the tide uncovers the salt road to the Lantern Isles. Iska Venn has one crossing to find the missing lighthouse keeper and get back before the sea returns."
    case Demo.harborOfBells.id:
      "Every ship in Vell is rung home by its own bell. Iska hears one nobody else can, ringing for a ship lost forty years ago."
    case Demo.ninthTide.id:
      "The ninth tide of the year rises higher than any before it, and the Lantern Isles must choose which shores to give up."
    case Demo.stormglass.id:
      "The fourth Tidewater Saga novel. Mara Kessling returns to the Lantern Isles in June 2027."
    default:
      "\(title) by \(author)."
    }
  }

  var detailAddedOn: String? {
    guard inLibrary else { return nil }
    return id == Demo.saltRoad.id ? "Nov 2" : "Sep 20"
  }
}

#Preview {
  NavigationStack {
    SirenBookDetailView(book: Demo.saltRoad, onSend: {}, onPlay: {})
  }
  .tint(SirenTheme.tint)
}
