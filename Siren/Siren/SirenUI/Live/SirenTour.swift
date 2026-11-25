import SwiftUI

/// The welcome tour: what Siren is, covers that ink in as you listen, and the art the player
/// opens on. New listeners finish on Connect to Server. Everyone else sees it once, and can
/// replay it from Progress Art & Goal.
struct SirenTour: View {
  enum Ending { case connect, done }
  enum Page: Int, CaseIterable { case welcome, covers, player }

  let ending: Ending

  @AppStorage(SirenSettings.tourSeen) private var seen = false
  @Environment(\.dismiss) private var dismiss
  @State private var page: Page
  @State private var serverModel: ServerView.Model?
  @State private var infoModel: AudiobookshelfInfoView.Model?

  init(ending: Ending, startPage: Page = .welcome) {
    self.ending = ending
    _page = State(initialValue: startPage)
  }

  var body: some View {
    NavigationStack {
      TabView(selection: $page) {
        SirenTourWelcome()
          .tag(Page.welcome)
        SirenTourCovers(isCurrent: page == .covers)
          .tag(Page.covers)
        SirenTourPlayer()
          .tag(Page.player)
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .background(SirenTheme.ground.ignoresSafeArea())
      .safeAreaInset(edge: .bottom) { footer }
      .toolbar(.hidden, for: .navigationBar)
      .navigationDestination(item: $serverModel) { ServerView(model: $0) }
      .navigationDestination(item: $infoModel) { AudiobookshelfInfoView(model: $0) }
    }
    .tint(SirenTheme.tint)
    .onChange(of: page) { _, page in
      if page == .player { seen = true }
    }
  }

  private var footer: some View {
    VStack(spacing: 10) {
      dots
        .padding(.bottom, 6)
      Button(action: primary) {
        Text(primaryTitle)
          .font(.headline)
          .foregroundStyle(SirenTheme.onTint)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      // Always there, so the footer keeps its height from page to page.
      Button(action: secondary) {
        Text(secondaryTitle)
          .font(.subheadline)
          .frame(maxWidth: .infinity, minHeight: 36)
      }
      .opacity(hasSecondary ? 1 : 0)
      .disabled(!hasSecondary)
      .accessibilityHidden(!hasSecondary)
    }
    .frame(maxWidth: 520)
    .padding(.horizontal, 24)
    .padding(.top, 8)
    .frame(maxWidth: .infinity)
    .background(SirenTheme.ground)
  }

  private var dots: some View {
    HStack(spacing: 8) {
      ForEach(Page.allCases, id: \.self) { dot in
        Circle()
          .fill(dot == page ? SirenTheme.tint : SirenTheme.secondary.opacity(0.3))
          .frame(width: 7, height: 7)
      }
    }
    .animation(.easeOut(duration: 0.2), value: page)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Page \(page.rawValue + 1) of \(Page.allCases.count)")
  }

  private var isLast: Bool { page == .player }

  private var primaryTitle: LocalizedStringKey {
    if !isLast { return "Continue" }
    return ending == .connect ? "Connect to Server" : "Done"
  }

  private var secondaryTitle: LocalizedStringKey {
    isLast ? "I don't have a server yet" : "Skip"
  }

  private var hasSecondary: Bool { !isLast || ending == .connect }

  private func primary() {
    if let next = Page(rawValue: page.rawValue + 1) {
      withAnimation(.easeOut(duration: 0.3)) { page = next }
    } else if ending == .connect {
      serverModel = ServerViewModel()
    } else {
      dismiss()
    }
  }

  private func secondary() {
    if isLast {
      infoModel = AudiobookshelfInfoView.Model()
      return
    }
    seen = true
    if ending == .connect {
      withAnimation(.easeOut(duration: 0.3)) { page = .player }
    } else {
      dismiss()
    }
  }
}

/// One page: art in a fixed-height frame (so titles line up as you swipe), then the words, then
/// any choice the page asks for.
private struct SirenTourPage<Art: View, Controls: View>: View {
  let title: LocalizedStringKey
  let message: LocalizedStringKey
  @ViewBuilder var art: Art
  @ViewBuilder var controls: Controls

  static var artHeight: CGFloat { 300 }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        art
          .frame(height: Self.artHeight)
          .padding(.top, 28)
        VStack(spacing: 10) {
          Text(title)
            .font(.title.bold())
            .foregroundStyle(SirenTheme.ink)
          Text(message)
            .font(.body)
            .foregroundStyle(SirenTheme.secondary)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, 32)
        controls
          .padding(.top, 24)
      }
      .frame(maxWidth: 520)
      .padding(.horizontal, 24)
      .padding(.bottom, 16)
      .frame(maxWidth: .infinity)
    }
    .scrollBounceBehavior(.basedOnSize)
  }
}

/// Three books on a shelf at three points: finished, part-way, not started.
private struct SirenTourWelcome: View {
  var body: some View {
    SirenTourPage(
      title: "Welcome to Siren",
      message:
        "Listen to the books on your Audiobookshelf server, pick up where you left off on any device, and send a book to anyone who shares the server."
    ) {
      ZStack {
        RevealCover(book: Demo.harborOfBells, progress: 1, resolution: .large)
          .frame(width: 150)
          .rotationEffect(.degrees(-7))
          .offset(x: -106, y: 16)
        RevealCover(book: Demo.ninthTide, progress: 0, resolution: .large)
          .frame(width: 150)
          .rotationEffect(.degrees(7))
          .offset(x: 106, y: 16)
        RevealCover(book: Demo.saltRoad, progress: 0.57, resolution: .large)
          .frame(width: 200)
      }
      .accessibilityHidden(true)
    } controls: {
      EmptyView()
    }
  }
}

/// The reveal, shown on a cover you can ink in yourself, and the choice to keep covers plain.
private struct SirenTourCovers: View {
  let isCurrent: Bool

  @AppStorage(SirenSettings.coverReveal) private var revealsProgress = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var progress = 0.08
  @State private var hasInked = false

  var body: some View {
    SirenTourPage(
      title: "Covers ink in as you listen",
      message:
        "Every book starts as a pencil sketch and fills with colour as you go, so you can see how far you've got at a glance. Only you see your progress."
    ) {
      VStack(spacing: 14) {
        InkingCover(book: Demo.saltRoad, progress: progress)
          .frame(width: 228)
        VStack(spacing: 2) {
          Slider(value: $progress, in: 0...1) {
            Text("Listening progress")
          }
          .accessibilityValue("\(Int((progress * 100).rounded())) percent")
          Text("Drag to listen")
            .font(.footnote)
            .foregroundStyle(SirenTheme.secondary)
        }
        .frame(width: 228)
        // Kept in place when covers are plain, so nothing below moves.
        .opacity(revealsProgress ? 1 : 0)
        .disabled(!revealsProgress)
        .accessibilityHidden(!revealsProgress)
      }
    } controls: {
      Picker("Covers", selection: $revealsProgress) {
        Text("Ink in as you listen").tag(true)
        Text("Plain covers").tag(false)
      }
      .pickerStyle(.segmented)
    }
    .onChange(of: isCurrent, initial: true) { _, isCurrent in
      guard isCurrent, !hasInked else { return }
      hasInked = true
      if reduceMotion {
        progress = 0.57
      } else {
        withAnimation(.easeOut(duration: 2.4).delay(0.3)) { progress = 0.57 }
      }
    }
  }
}

/// RevealCover with its progress animatable, so the sketch inks in rather than jumping.
private struct InkingCover: View, Animatable {
  let book: SirenBook
  var progress: Double

  var animatableData: Double {
    get { progress }
    set { progress = newValue }
  }

  var body: some View {
    RevealCover(book: book, progress: progress, showTicks: true, resolution: .large)
  }
}

/// The player's three art views, previewed at the size of the real thing.
private struct SirenTourPlayer: View {
  @AppStorage(SirenSettings.playerArt) private var playerArt: PlayerArt = .cover

  var body: some View {
    SirenTourPage(
      title: "Choose the player's art",
      message:
        "Pick what the player opens on; you can swipe the art to switch. Change it later in Progress Art & Goal, under your profile on Home."
    ) {
      preview
        .frame(width: Self.side, height: Self.side)
        .animation(.easeOut(duration: 0.25), value: playerArt)
    } controls: {
      VStack(spacing: 12) {
        Picker("Player art", selection: $playerArt) {
          ForEach(PlayerArt.allCases) { art in
            Text(art.label).tag(art)
          }
        }
        .pickerStyle(.segmented)
        Text(detail)
          .font(.footnote)
          .foregroundStyle(SirenTheme.secondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  private static let side: CGFloat = 280

  @ViewBuilder private var preview: some View {
    let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    ZStack {
      switch playerArt {
      case .cover:
        RevealCover(book: Demo.saltRoad, showTicks: true, cornerRadius: 10, resolution: .large)
          .transition(.opacity)
      case .map:
        FogMapArt(book: Demo.saltRoad)
          .clipShape(shape)
          .overlay { shape.strokeBorder(.black.opacity(0.08), lineWidth: 0.5) }
          .transition(.opacity)
      case .voice:
        VoicePrintView(book: Demo.saltRoad)
          .clipShape(shape)
          .transition(.opacity)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var detail: LocalizedStringKey {
    switch playerArt {
    case .cover: "The cover, large, with a mark at the start of each chapter."
    case .map: "A map drawn for each book. The fog lifts along the route as you listen."
    case .voice:
      "A ridge for each chapter, drawn from the book's audio. Downloaded books only; streamed books show the cover."
    }
  }
}
