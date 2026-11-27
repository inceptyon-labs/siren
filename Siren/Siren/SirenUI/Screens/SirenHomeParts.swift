import SwiftUI

/// One Home section: a hairline above it (not on the first), the title, then the content. The
/// title sits close to its content and far from the section before, so each shelf reads as one.
struct SirenHomeSection<Content: View>: View {
  let title: String
  var divided = true
  @ViewBuilder var content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if divided {
        Rectangle()
          .fill(SirenTheme.separator)
          .frame(height: 0.5)
          .padding(.bottom, 10)
          .accessibilityHidden(true)
      }
      Text(title)
        .font(SirenType.display(.title2))
        .foregroundStyle(SirenTheme.heading)
        .accessibilityAddTraits(.isHeader)
      content
    }
    .padding(.top, divided ? 24 : 4)
  }
}

extension View {
  /// The tab bar already says Home, so the page opens on what you're listening to, not a title.
  func sirenHomeTitle() -> some View {
    navigationTitle("Home")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .principal) {
          Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
        }
      }
  }
}

/// Books as an inset group of rows: a small cover, the title, one line of detail, and Resume when
/// the row can start playing.
struct SirenBookRows: View {
  let books: [SirenBook]
  /// Rows shown before Show More.
  var limit = 4
  var detail: (SirenBook) -> String
  var onOpen: (SirenBook) -> Void
  var onResume: ((SirenBook) -> Void)?

  @State private var showsAll = false

  var body: some View {
    let shown = showsAll ? books : Array(books.prefix(limit))
    VStack(spacing: 0) {
      ForEach(Array(shown.enumerated()), id: \.element.id) { index, book in
        row(book)
        if index < shown.count - 1 {
          Divider().padding(.leading, 68)
        }
      }
      if shown.count < books.count {
        Divider()
        Button("Show \(books.count - shown.count) More") {
          withAnimation(.snappy) { showsAll = true }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(SirenTheme.tint)
        .frame(maxWidth: .infinity, minHeight: 44)
      }
    }
    .background(SirenTheme.raised, in: RoundedRectangle(cornerRadius: SirenTheme.rowRadius, style: .continuous))
  }

  private func row(_ book: SirenBook) -> some View {
    HStack(spacing: 12) {
      Button {
        onOpen(book)
      } label: {
        HStack(spacing: 12) {
          RevealCover(book: book, cornerRadius: 4, shadow: false)
            .frame(width: 44, height: 44)
          VStack(alignment: .leading, spacing: 3) {
            Text(book.title)
              .font(SirenType.bookTitle(.headline))
              .foregroundStyle(SirenTheme.ink)
              .lineLimit(1)
            let line = detail(book)
            if !line.isEmpty {
              Text(line)
                .font(.footnote)
                .foregroundStyle(SirenTheme.secondary)
                .monospacedDigit()
                .lineLimit(1)
            }
          }
          Spacer(minLength: 8)
          if onResume == nil {
            Image(systemName: "chevron.right")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(SirenTheme.secondary.opacity(0.6))
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityElement(children: .combine)

      if let onResume {
        Button {
          onResume(book)
        } label: {
          Image(systemName: "play.fill")
            .font(.footnote.weight(.bold))
            .foregroundStyle(SirenTheme.onTint)
            .frame(width: 32, height: 32)
            .background(SirenTheme.tint, in: Circle())
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Resume \(book.title)"))
      }
    }
    .padding(.leading, 12)
    .padding(.trailing, onResume == nil ? 12 : 6)
    .padding(.vertical, onResume == nil ? 10 : 4)
    .frame(minHeight: 64)
  }
}

/// Home's lead: the book you're in, half inked, with Resume.
struct SirenContinueCard: View {
  let book: SirenBook
  var isPlaying = false
  var onOpen: () -> Void
  var onResume: () -> Void

  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var tint: Color?

  var body: some View {
    details
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      // The card takes its color from the cover, so the book you're in leads Home in its own color.
      .background(
        tint ?? SirenTheme.raised,
        in: RoundedRectangle(cornerRadius: SirenTheme.rowRadius, style: .continuous)
      )
      .animation(.easeOut(duration: 0.35), value: tint)
      .task(id: book.id) {
        tint = await CoverStore.shared.tint(for: book).map(Color.init(uiColor:))
      }
  }

  @ViewBuilder private var details: some View {
    // At accessibility text sizes the details need the full width, so they go under the cover.
    let layout =
      typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
      : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
    layout {
      Button(action: onOpen) {
        RevealCover(book: book, showTicks: true, resolution: .large)
          .frame(width: 150, height: 150)
      }
      .buttonStyle(.plain)

      VStack(alignment: .leading, spacing: 4) {
        Text(book.title)
          .font(SirenType.bookTitle(.title2))
          .foregroundStyle(SirenTheme.ink)
          .lineLimit(3)
        Text(book.author)
          .font(.subheadline)
          .foregroundStyle(SirenTheme.secondary)
          .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
        if book.chapterCount > 1, !book.chapterRemaining.isEmpty {
          Text("Ch \(book.currentChapter) · \(book.chapterRemaining) left")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(SirenTheme.ink)
            .monospacedDigit()
            .padding(.top, 8)
        }
        if !book.timeLeft.isEmpty {
          Text("\(book.timeLeft) left in book")
            .font(.footnote)
            .foregroundStyle(SirenTheme.secondary)
            .padding(.top, book.chapterCount > 1 ? 0 : 8)
        }
        Button(action: onResume) {
          Label(isPlaying ? "Pause" : "Resume", systemImage: isPlaying ? "pause.fill" : "play.fill")
            .font(SirenType.display(.headline))
            .foregroundStyle(SirenTheme.onTint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .padding(.top, 10)
      }
    }
  }
}

/// Home's lead on iPhone: the book you're in, full width and up under the status bar, then a band
/// in the cover's own color with the chapter and Resume.
struct SirenNowHeader: View {
  let book: SirenBook
  var isPlaying = false
  var onOpen: () -> Void
  var onResume: () -> Void

  @AppStorage(SirenSettings.coverReveal) private var revealsProgress = true
  @State private var band: Color?

  /// Gray covers and covers still loading get the heading teal.
  private var bandColor: Color { band ?? Color(sirenHex: 0x17474E) }

  var body: some View {
    VStack(spacing: 0) {
      Button(action: onOpen) {
        RevealCover(book: book, showTicks: true, cornerRadius: 0, shadow: false, resolution: .large)
          .overlay(alignment: .top) {
            // Keeps the status bar and the profile button readable on any cover.
            LinearGradient(colors: [.black.opacity(0.5), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
              .frame(height: 150)
              .allowsHitTesting(false)
          }
          .overlay(alignment: .bottom) {
            // With the reveal off the cover can't show how far in you are, so a bar does.
            if !revealsProgress {
              GeometryReader { proxy in
                Rectangle()
                  .fill(.white)
                  .frame(width: proxy.size.width * book.progress, height: 4)
              }
              .frame(height: 4)
            }
          }
      }
      .buttonStyle(.plain)

      details
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bandColor)
    }
    .animation(.easeOut(duration: 0.35), value: band)
    .task(id: book.id) {
      band = await CoverStore.shared.band(for: book).map(Color.init(uiColor:))
    }
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: 4) {
      Button(action: onOpen) {
        VStack(alignment: .leading, spacing: 5) {
          Text(book.title)
            .font(SirenType.bookTitle(.largeTitle))
            .foregroundStyle(.white)
            .lineLimit(3)
          Text(book.author)
            .font(.subheadline)
            .foregroundStyle(.white.opacity(0.75))
            .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if book.chapterCount > 1 {
        Text(chapterLine)
          .font(SirenType.display(.title3, weight: .medium).italic())
          .foregroundStyle(.white)
          .lineLimit(2)
          .padding(.top, 12)
      }
      if !timeLine.isEmpty {
        Text(timeLine)
          .font(.footnote)
          .foregroundStyle(.white.opacity(0.75))
          .monospacedDigit()
          .padding(.top, book.chapterCount > 1 ? 0 : 12)
      }

      HStack(spacing: 14) {
        Button(action: onResume) {
          Label(isPlaying ? "Pause" : "Resume", systemImage: isPlaying ? "pause.fill" : "play.fill")
            .font(SirenType.display(.headline))
            .foregroundStyle(bandColor)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .background(.white, in: Capsule())
        }
        .buttonStyle(.plain)
        Text("\(Int((book.progress * 100).rounded()))%")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white.opacity(0.75))
          .monospacedDigit()
          .accessibilityLabel("\(Int((book.progress * 100).rounded())) percent listened")
      }
      .padding(.top, 14)
    }
  }

  /// "Chapter 14, The Spice Harvest", or just the title when it already names the chapter.
  private var chapterLine: String {
    let title = book.chapterTitle.trimmingCharacters(in: .whitespaces)
    if title.isEmpty || title.allSatisfy(\.isNumber) { return "Chapter \(book.currentChapter)" }
    if title.lowercased().hasPrefix("chapter") { return title }
    return "Chapter \(book.currentChapter), \(title)"
  }

  private var timeLine: String {
    var parts: [String] = []
    if book.chapterCount > 1, !book.chapterRemaining.isEmpty {
      parts.append("\(book.chapterRemaining) left in chapter")
    }
    if !book.timeLeft.isEmpty { parts.append("\(book.timeLeft) left in book") }
    return parts.joined(separator: " · ")
  }
}

/// The personal yearly goal: a slot per book, filled with the covers finished so far.
struct SirenGoalCard: View {
  enum Unit { case books, hours }

  /// Finished books, newest last. Only the first `goal` get a slot.
  let finished: [SirenBook]
  /// Books finished, or hours listened.
  let count: Int
  let goal: Int
  var unit: Unit = .books

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 10)

  private var year: Int { Calendar.current.component(.year, from: .now) }

  private var daysLeft: Int {
    let calendar = Calendar.current
    guard let nextYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) else { return 0 }
    return calendar.dateComponents([.day], from: calendar.startOfDay(for: .now), to: nextYear).day ?? 0
  }

  private var status: String {
    if count >= goal { return "\(String(year)) goal reached" }
    return "\(String(year)) goal · \(goal - count) to go · \(daysLeft) days left"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text("\(count)")
          .font(SirenType.display(.largeTitle, weight: .bold))
          .foregroundStyle(SirenTheme.ink)
          .monospacedDigit()
        Text(unit == .books ? "of \(goal) books" : "of \(goal) hours")
          .font(SirenType.display(.headline))
          .foregroundStyle(SirenTheme.ink)
        Spacer()
        Image(systemName: "chevron.right")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(SirenTheme.secondary.opacity(0.6))
      }
      Text(status)
        .font(.subheadline)
        .foregroundStyle(SirenTheme.secondary)
      if unit == .books, goal <= 60 {
        LazyVGrid(columns: columns, spacing: 6) {
          ForEach(0..<goal, id: \.self) { index in
            if index < finished.count {
              RevealCover(book: finished[index], progress: 1, cornerRadius: 3, shadow: false)
            } else if index < count {
              // Finished, but the server has no cover for it.
              RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(SirenTheme.paper)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                  Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(SirenTheme.graphite)
                }
            } else {
              RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(SirenTheme.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .aspectRatio(1, contentMode: .fit)
            }
          }
        }
      } else {
        ProgressView(value: Double(min(count, goal)), total: Double(max(goal, 1)))
          .tint(SirenTheme.tint)
      }
    }
    .padding(16)
    .background(SirenTheme.raised, in: RoundedRectangle(cornerRadius: SirenTheme.rowRadius, style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      unit == .books
        ? "\(String(year)) goal: \(count) of \(goal) books finished"
        : "\(String(year)) goal: \(count) of \(goal) hours listened"
    )
  }
}

/// A horizontal row of covers with titles.
struct SirenCoverShelf: View {
  let books: [SirenBook]
  var side: CGFloat = 120
  var onOpen: (SirenBook) -> Void

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      LazyHStack(alignment: .top, spacing: 14) {
        ForEach(books) { book in
          Button {
            onOpen(book)
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              RevealCover(book: book)
                .frame(width: side, height: side)
              Text(book.title)
                .font(SirenType.bookTitle(.footnote))
                .foregroundStyle(SirenTheme.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
              if !book.author.isEmpty {
                Text(book.author)
                  .font(.caption)
                  .foregroundStyle(SirenTheme.secondary)
                  .lineLimit(1)
              }
            }
            .frame(width: side, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text("\(book.title), \(book.author)"))
        }
      }
    }
    .scrollClipDisabled()
  }
}

/// Body text clipped to a few lines, with More only when the clip actually hides something.
struct SirenExpandableText: View {
  let text: String
  var lineLimit = 6

  @State private var isExpanded = false
  @State private var isTruncated = false

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(text)
        .font(.body)
        .foregroundStyle(SirenTheme.ink)
        .lineLimit(isExpanded ? nil : lineLimit)
        .fixedSize(horizontal: false, vertical: true)
        .background {
          // The full text fits in the clipped frame only when nothing is hidden.
          ViewThatFits(in: .vertical) {
            Text(text)
              .font(.body)
              .fixedSize(horizontal: false, vertical: true)
              .hidden()
              .onAppear { isTruncated = false }
            Color.clear
              .onAppear { isTruncated = true }
          }
          .id(text)
        }
      if isTruncated, !isExpanded {
        Button("More") { isExpanded = true }
          .font(.subheadline.weight(.semibold))
      }
    }
  }
}
