import Foundation
import SwiftUI

/// What the player's transport shows and does. Demo screens pass fixed values; the live player
/// reads them from upstream's `BookPlayer.Model`.
struct SirenPlayback {
  var isPlaying = true
  var isLoading = false
  /// Scrubber position, 0...1 of the chapter (or of the book, per the player preference).
  var position: Double = 0
  var elapsed = ""
  var remaining = ""
  var bookLeft = ""
  var skipBack = 30
  var skipForward = 30
  var speed = "1×"
  /// Sleep timer label; nil when the timer is off.
  var sleep: String?
  var canGoPreviousChapter = true
  var canGoNextChapter = true

  /// Called while dragging (`true`) and once on release (`false`).
  var onScrub: (Double, Bool) -> Void = { _, _ in }
  var onTogglePlay: () -> Void = {}
  var onSkipBack: () -> Void = {}
  var onSkipForward: () -> Void = {}
  var onPreviousChapter: () -> Void = {}
  var onNextChapter: () -> Void = {}
  var onSpeed: () -> Void = {}
  var onSleep: () -> Void = {}
  var onBookmarks: () -> Void = {}
  var onChapters: () -> Void = {}
}

struct SirenPlayerView<MoreMenu: View>: View {
  let book: SirenBook
  let playback: SirenPlayback
  var pages: [PlayerArt] = PlayerArt.allCases
  /// Bookmarks as fractions of the book, planted as flags on the map.
  var flags: [Double] = []
  /// The voice print's ridges from the book's audio; nil draws the demo's.
  var voiceRidges: [[Double]?]?
  /// Set for a streamed book: the voice print needs its audio on the device.
  var voiceDownload: VoicePrintView.Download?
  @Binding var art: PlayerArt
  @ViewBuilder var moreMenu: () -> MoreMenu

  var body: some View {
    GeometryReader { geo in
      if geo.size.width > geo.size.height * 1.1 {
        HStack(spacing: 40) {
          VStack(spacing: 14) {
            artArea(side: min(geo.size.height - 120, geo.size.width * 0.48))
            pageDots
          }
          controls
            .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        let side = min(geo.size.width - 48, geo.size.height - 400, 720)
        VStack(spacing: 0) {
          artArea(side: side)
            .padding(.top, 28)
          pageDots
            .padding(.top, 14)
          controls
            .frame(maxWidth: max(side, 354))
        }
        .frame(maxWidth: .infinity)
      }
    }
    .background(SirenTheme.ground)
    .environment(\.colorScheme, .dark)
    .tint(SirenTheme.tint)
  }

  private var byline: String {
    book.narrator.isEmpty ? book.author : "\(book.author) · read by \(book.narrator)"
  }

  private var chapterLine: String? {
    guard book.chapterCount > 1 else { return nil }
    return book.chapterTitle.isEmpty
      ? "Ch \(book.currentChapter)" : "Ch \(book.currentChapter) · \(book.chapterTitle)"
  }

  private var controls: some View {
    VStack(spacing: 0) {

      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          Text(book.title)
            .font(SirenType.bookTitle(.title))
            .foregroundStyle(SirenTheme.ink)
            .lineLimit(2)
          Spacer()
          Menu(content: moreMenu) {
            Image(systemName: "ellipsis")
              .font(.title3.weight(.semibold))
              .foregroundStyle(SirenTheme.ink)
              .frame(width: 44, height: 44)
              .contentShape(Rectangle())
          }
          // Borderless with no arrow, also on the Mac, where a menu is otherwise a pull-down button.
          .menuStyle(.button)
          .buttonStyle(.borderless)
          .menuIndicator(.hidden)
          .foregroundStyle(SirenTheme.ink)
          .accessibilityLabel("More")
        }
        Text(byline)
          .font(.subheadline)
          .foregroundStyle(SirenTheme.secondary)
          .lineLimit(1)
        if let chapterLine {
          Text(chapterLine)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(SirenTheme.ink)
            .lineLimit(1)
            .padding(.top, 2)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 24)
      .padding(.top, 18)

      scrubber
        .padding(.horizontal, 24)
        .padding(.top, 14)

      transport
        .padding(.top, 18)
        .disabled(playback.isLoading)

      Spacer(minLength: 12)

      utilityRow
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
  }

  @ViewBuilder private func artArea(side: CGFloat) -> some View {
    if pages.count > 1 {
      TabView(selection: $art) {
        ForEach(pages) { page in
          artPage(page)
            .padding(4)
            .tag(page)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .frame(width: side + 8, height: side + 8)
    } else {
      artPage(.cover)
        .padding(4)
        .frame(width: side + 8, height: side + 8)
    }
  }

  @ViewBuilder private func artPage(_ page: PlayerArt) -> some View {
    switch page {
    case .cover:
      RevealCover(book: book, showTicks: true, cornerRadius: 10, resolution: .large)
    case .map:
      FogMapArt(book: book, flags: flags)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    case .voice:
      VoicePrintView(book: book, ridges: voiceDownload == nil ? voiceRidges : [], download: voiceDownload)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
  }

  @ViewBuilder private var pageDots: some View {
    if pages.count > 1 {
      HStack(spacing: 8) {
        ForEach(pages) { item in
          Circle()
            .fill(item == art ? SirenTheme.tint : SirenTheme.secondary.opacity(0.45))
            .frame(width: 7, height: 7)
        }
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text("Art view: ") + Text(art.label))
    }
  }

  private var scrubber: some View {
    VStack(spacing: 6) {
      Slider(
        value: Binding(get: { playback.position }, set: { playback.onScrub($0, true) }),
        onEditingChanged: { editing in
          if !editing { playback.onScrub(playback.position, false) }
        }
      )
      .tint(SirenTheme.tint)
      HStack {
        Text(playback.elapsed)
        Spacer()
        Text("\(playback.bookLeft) left in book")
        Spacer()
        Text("−\(playback.remaining)")
      }
      .font(.caption.weight(.medium))
      .monospacedDigit()
      .foregroundStyle(SirenTheme.secondary)
    }
  }

  private var transport: some View {
    HStack(spacing: 0) {
      transportButton("backward.end.fill", label: "Previous chapter", size: .title2, action: playback.onPreviousChapter)
        .disabled(!playback.canGoPreviousChapter)
      transportButton(
        "gobackward.\(playback.skipBack)",
        label: "Back \(playback.skipBack) seconds",
        size: .largeTitle,
        action: playback.onSkipBack
      )
      Button(action: playback.onTogglePlay) {
        Group {
          if playback.isLoading {
            ProgressView().tint(SirenTheme.onTint)
          } else {
            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
              .font(.system(size: 30, weight: .bold))
          }
        }
        .foregroundStyle(SirenTheme.onTint)
        .frame(width: 76, height: 76)
        .background(SirenTheme.tint, in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
      .frame(maxWidth: .infinity)
      transportButton(
        "goforward.\(playback.skipForward)",
        label: "Forward \(playback.skipForward) seconds",
        size: .largeTitle,
        action: playback.onSkipForward
      )
      transportButton("forward.end.fill", label: "Next chapter", size: .title2, action: playback.onNextChapter)
        .disabled(!playback.canGoNextChapter)
    }
    .padding(.horizontal, 12)
  }

  private func transportButton(
    _ symbol: String,
    label: String,
    size: Font,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(size.weight(.regular))
        .frame(width: 56, height: 56)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(SirenTheme.ink)
    .accessibilityLabel(label)
    .frame(maxWidth: .infinity)
  }

  private var utilityRow: some View {
    HStack {
      Button(action: playback.onSpeed) {
        Text(playback.speed).font(.headline).monospacedDigit()
      }
      .accessibilityLabel("Speed \(playback.speed)")
      Spacer()
      Button(action: playback.onSleep) {
        if let sleep = playback.sleep {
          Label(sleep, systemImage: "moon.zzz.fill").font(.subheadline.weight(.semibold)).monospacedDigit()
        } else {
          Image(systemName: "moon.zzz").font(.title3).frame(width: 44, height: 44)
        }
      }
      .accessibilityLabel(playback.sleep.map { "Sleep timer, \($0)" } ?? "Sleep timer")
      Spacer()
      AirPlayButton()
        .frame(width: 44, height: 44)
        .accessibilityLabel("AirPlay")
      Spacer()
      utility("bookmark", "Bookmarks", action: playback.onBookmarks)
      Spacer()
      utility("list.bullet", "Chapters", action: playback.onChapters)
        .disabled(book.chapterCount < 2)
    }
    .foregroundStyle(SirenTheme.tint)
    // No bezels on the Mac.
    .buttonStyle(.borderless)
    .frame(minHeight: 44)
  }

  private func utility(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.title3)
        .frame(width: 44, height: 44)
    }
    .foregroundStyle(SirenTheme.ink)
    .accessibilityLabel(label)
  }
}

/// One ridgeline per chapter. Heard chapters are inked; the current one up to the playhead.
/// Ridges come from the book's audio (`SirenVoicePrint`); a chapter not read yet is a flat dotted
/// line. Without ridges (the demo), envelopes are synthetic, seeded from the book ID.
struct VoicePrintView: View {
  static let samples = 150

  /// A streamed book's way to the voice print: download it, then its audio can be read.
  struct Download {
    /// 0–1 while downloading, nil before.
    var progress: Double?
    var start: () -> Void
  }

  let book: SirenBook
  var ridges: [[Double]?]?
  var download: Download?

  /// Chapters whose audio hasn't been read yet, while the scan works through the book.
  private var unread: Int {
    guard download == nil, let ridges else { return 0 }
    return ridges.filter { $0 == nil }.count
  }

  var body: some View {
    // The prompt sits outside the print's single accessibility element, so VoiceOver reaches it.
    ridgelines
      .overlay {
        if let download {
          downloadPrompt(download)
        }
      }
  }

  private var ridgelines: some View {
    ZStack(alignment: .topTrailing) {
      Canvas { ctx, size in
        let count = book.chapterCount
        let left: CGFloat = 30
        let right = size.width - 12
        let top: CGFloat = 70
        let spacing = (size.height - top - 14) / CGFloat(count)
        let peak = spacing * 2.3
        let samples = Self.samples
        let ink = Color(sirenHex: 0xF2F2F0)
        let faint = Color(sirenHex: 0xA3A8B2)
        let ground = Color(sirenHex: 0x1C1F24)

        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ground))

        for chapter in 0..<count {
          let baseline = top + spacing * CGFloat(chapter + 1)
          let (env, isRead) = ridge(chapter, samples: samples)
          var line = Path()
          for (i, v) in env.enumerated() {
            let x = left + (right - left) * CGFloat(i) / CGFloat(samples - 1)
            let point = CGPoint(x: x, y: baseline - CGFloat(v) * peak)
            i == 0 ? line.move(to: point) : line.addLine(to: point)
          }
          var fill = line
          fill.addLine(to: CGPoint(x: right, y: size.height))
          fill.addLine(to: CGPoint(x: left, y: size.height))
          fill.closeSubpath()
          ctx.fill(fill, with: .color(ground))

          let number = chapter + 1
          if number < book.currentChapter, isRead {
            ctx.stroke(line, with: .color(ink), lineWidth: 1.1)
          } else if number == book.currentChapter {
            let head = left + (right - left) * book.chapterProgress
            ctx.stroke(line, with: .color(faint.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [1, 2.5]))
            if isRead {
              var heard = ctx
              heard.clip(to: Path(CGRect(x: 0, y: 0, width: head, height: size.height)))
              heard.stroke(line, with: .color(ink), lineWidth: 1.1)
            }
            let index = Int(book.chapterProgress * Double(samples - 1))
            let y = baseline - CGFloat(env[index]) * peak
            ctx.fill(
              Path(ellipseIn: CGRect(x: head - 4, y: y - 4, width: 8, height: 8)),
              with: .color(SirenTheme.tint)
            )
          } else {
            ctx.stroke(line, with: .color(faint.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [1, 2.5]))
          }

          if number % 5 == 0 {
            let label = ctx.resolve(
              Text("\(number)").font(.system(size: 9, weight: .medium)).foregroundColor(faint.opacity(0.8))
            )
            ctx.draw(label, at: CGPoint(x: 14, y: baseline - 3), anchor: .center)
          }
        }
      }

      RevealCover(book: book, progress: 1, cornerRadius: 4)
        .frame(width: 48, height: 48)
        .padding(10)
      VStack(alignment: .leading, spacing: 2) {
        Text("\(book.currentChapter - 1) of \(book.chapterCount) chapters heard")
        if unread > 0 {
          Text("Reading the audio, \(book.chapterCount - unread) of \(book.chapterCount) chapters")
        }
      }
      .font(.caption.weight(.medium))
      .foregroundStyle(Color(sirenHex: 0xA3A8B2))
      .monospacedDigit()
      .padding(.leading, 14)
      .padding(.top, 14)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "Voice print of \(book.title): \(book.currentChapter - 1) of \(book.chapterCount) chapters heard"
    )
  }

  private func downloadPrompt(_ download: Download) -> some View {
    VStack(spacing: 12) {
      Image(systemName: "waveform")
        .font(.title)
      Text("The voice print is drawn from the book's audio, so it needs the book on this device.")
        .font(.subheadline)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      if let progress = download.progress {
        ProgressView(value: progress)
          .tint(Color(sirenHex: 0x3FB6BF))
          .frame(maxWidth: 180)
        Text("Downloading, \(Int((progress * 100).rounded()))%")
          .font(.footnote)
          .monospacedDigit()
          .foregroundStyle(Color(sirenHex: 0xA3A8B2))
      } else {
        Button("Download", systemImage: "arrow.down.circle", action: download.start)
          .font(.headline)
          .buttonStyle(.borderedProminent)
          .buttonBorderShape(.capsule)
          .tint(Color(sirenHex: 0x3FB6BF))
          .foregroundStyle(Color(sirenHex: 0x111316))
      }
    }
    .foregroundStyle(Color(sirenHex: 0xF2F2F0))
    .padding(.horizontal, 32)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(sirenHex: 0x1C1F24).opacity(0.82))
  }

  /// The chapter's heights, and whether they come from its audio (or the demo) rather than a
  /// placeholder for a chapter not read yet.
  private func ridge(_ chapter: Int, samples: Int) -> (heights: [Double], isRead: Bool) {
    guard let ridges else { return (envelope(chapter: chapter, samples: samples), true) }
    if ridges.indices.contains(chapter), let ridge = ridges[chapter], ridge.count == samples { return (ridge, true) }
    return (Array(repeating: 0, count: samples), false)
  }

  /// Speech-shaped loudness: a quiet opening, phrases separated by pauses, louder scenes.
  private func envelope(chapter: Int, samples: Int) -> [Double] {
    var rng = SeededRandom(seed: UInt64(book.id.sirenSeed &+ chapter &* 7919))
    var raw = [Double](repeating: 0, count: samples)
    var i = Int(Double(samples) * 0.06)
    let sceneStart = Int(rng.next() * Double(samples))
    let sceneLength = Int(10 + rng.next() * 18)
    while i < samples - 3 {
      let phrase = Int(4 + rng.next() * 12)
      let scene = (sceneStart..<(sceneStart + sceneLength)).contains(i)
      let level = (scene ? 0.55 : 0.25) + rng.next() * (scene ? 0.45 : 0.4)
      for k in 0..<phrase where i + k < samples {
        let shape = sin(Double(k) / Double(phrase) * .pi)
        raw[i + k] = level * (0.55 + 0.45 * shape) * (0.7 + 0.3 * rng.next())
      }
      i += phrase + Int(1 + rng.next() * 4)
    }
    let fadeStart = Int(Double(samples) * 0.9)
    for j in fadeStart..<samples {
      raw[j] *= Double(samples - j) / Double(samples - fadeStart)
    }
    return raw.indices.map { j in
      let lo = max(0, j - 2)
      let hi = min(samples - 1, j + 2)
      return raw[lo...hi].reduce(0, +) / Double(hi - lo + 1)
    }
  }
}

#Preview {
  SirenPlayerView(book: Demo.saltRoad, playback: Demo.playback, art: .constant(.voice)) {
    Button("Car Mode", systemImage: "car") {}
  }
}
