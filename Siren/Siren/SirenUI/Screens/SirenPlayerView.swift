import Foundation
import SwiftUI

struct SirenPlayerView: View {
  @Binding var art: PlayerArt
  var onCarMode: () -> Void

  private let book = Demo.saltRoad
  @State private var scrub = Demo.saltRoad.chapterProgress

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

  private var controls: some View {
    VStack(spacing: 0) {

      VStack(alignment: .leading, spacing: 4) {
        HStack(alignment: .firstTextBaseline) {
          Text(book.title)
            .font(SirenType.bookTitle(.title))
            .foregroundStyle(SirenTheme.ink)
          Spacer()
          moreMenu
        }
        Text("\(book.author) · read by \(book.narrator)")
          .font(.subheadline)
          .foregroundStyle(SirenTheme.secondary)
        Text("Ch \(book.currentChapter) · \(book.chapterTitle)")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(SirenTheme.ink)
          .padding(.top, 2)
      }
      .padding(.horizontal, 24)
      .padding(.top, 18)

      scrubber
        .padding(.horizontal, 24)
        .padding(.top, 14)

      transport
        .padding(.top, 18)

      Spacer(minLength: 12)

      utilityRow
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }
  }

  private func artArea(side: CGFloat) -> some View {
    TabView(selection: $art) {
      RevealCover(book: book, showTicks: true, cornerRadius: 10)
        .padding(4)
        .tag(PlayerArt.cover)
      Image("SirenDemoMapSaltRoad")
        .resizable()
        .scaledToFit()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(4)
        .accessibilityLabel("Map of The Salt Road, 57 percent uncovered")
        .tag(PlayerArt.map)
      VoicePrintView(book: book)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(4)
        .tag(PlayerArt.voice)
    }
    .tabViewStyle(.page(indexDisplayMode: .never))
    .frame(width: side + 8, height: side + 8)
  }

  private var pageDots: some View {
    HStack(spacing: 8) {
      ForEach(PlayerArt.allCases) { item in
        Circle()
          .fill(item == art ? SirenTheme.tint : SirenTheme.secondary.opacity(0.45))
          .frame(width: 7, height: 7)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Art view: \(art.label)")
  }

  private var moreMenu: some View {
    Menu {
      Button("Car Mode", systemImage: "car", action: onCarMode)
      Button("Send…", systemImage: "paperplane") {}
      Button("Go to Book", systemImage: "book") {}
    } label: {
      Image(systemName: "ellipsis")
        .font(.title3.weight(.semibold))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .foregroundStyle(SirenTheme.ink)
    .accessibilityLabel("More")
  }

  private var scrubber: some View {
    VStack(spacing: 6) {
      Slider(value: $scrub)
      HStack {
        Text("12:28")
        Spacer()
        Text("\(book.timeLeft) left in book")
        Spacer()
        Text("−\(book.chapterRemaining)")
      }
      .font(.caption.weight(.medium))
      .monospacedDigit()
      .foregroundStyle(SirenTheme.secondary)
    }
  }

  private var transport: some View {
    HStack(spacing: 0) {
      transportButton("backward.end.fill", label: "Previous chapter", size: .title2)
      transportButton("gobackward.30", label: "Back 30 seconds", size: .largeTitle)
      Button {
      } label: {
        Image(systemName: "pause.fill")
          .font(.system(size: 30, weight: .bold))
          .foregroundStyle(SirenTheme.onTint)
          .frame(width: 76, height: 76)
          .background(SirenTheme.tint, in: Circle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Pause")
      .frame(maxWidth: .infinity)
      transportButton("goforward.30", label: "Forward 30 seconds", size: .largeTitle)
      transportButton("forward.end.fill", label: "Next chapter", size: .title2)
    }
    .padding(.horizontal, 12)
  }

  private func transportButton(_ symbol: String, label: String, size: Font) -> some View {
    Button {
    } label: {
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
      Button {
      } label: {
        Text("1.3×").font(.headline).monospacedDigit()
      }
      .accessibilityLabel("Speed 1.3 times")
      Spacer()
      Button {
      } label: {
        Label("30 min", systemImage: "moon.zzz").font(.subheadline.weight(.semibold))
      }
      .accessibilityLabel("Sleep timer, 30 minutes")
      Spacer()
      utility("airplay.audio", "AirPlay")
      Spacer()
      utility("bookmark", "Add bookmark")
      Spacer()
      utility("list.bullet", "Chapters")
    }
    .foregroundStyle(SirenTheme.tint)
    .frame(minHeight: 44)
  }

  private func utility(_ symbol: String, _ label: String) -> some View {
    Button {
    } label: {
      Image(systemName: symbol)
        .font(.title3)
        .frame(width: 44, height: 44)
    }
    .foregroundStyle(SirenTheme.ink)
    .accessibilityLabel(label)
  }
}

/// One ridgeline per chapter. Heard chapters are inked; the current one up to the playhead.
/// Demo envelopes are synthetic, seeded from the book ID; the real ones come from the
/// loudness scan that trim silence already needs.
struct VoicePrintView: View {
  let book: DemoBook

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Canvas { ctx, size in
        let count = book.chapterCount
        let left: CGFloat = 30
        let right = size.width - 12
        let top: CGFloat = 70
        let spacing = (size.height - top - 14) / CGFloat(count)
        let peak = spacing * 2.3
        let samples = 150
        let ink = Color(sirenHex: 0xF2F2F0)
        let faint = Color(sirenHex: 0xA3A8B2)
        let ground = Color(sirenHex: 0x1C1F24)

        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(ground))

        for chapter in 0..<count {
          let baseline = top + spacing * CGFloat(chapter + 1)
          let env = envelope(chapter: chapter, samples: samples)
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
          if number < book.currentChapter {
            ctx.stroke(line, with: .color(ink), lineWidth: 1.1)
          } else if number == book.currentChapter {
            let head = left + (right - left) * book.chapterProgress
            ctx.stroke(line, with: .color(faint.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [1, 2.5]))
            var heard = ctx
            heard.clip(to: Path(CGRect(x: 0, y: 0, width: head, height: size.height)))
            heard.stroke(line, with: .color(ink), lineWidth: 1.1)
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
      Text("\(book.currentChapter - 1) of \(book.chapterCount) chapters heard")
        .font(.caption.weight(.medium))
        .foregroundStyle(Color(sirenHex: 0xA3A8B2))
        .padding(.leading, 14)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      "Voice print of \(book.title): \(book.currentChapter - 1) of \(book.chapterCount) chapters heard"
    )
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
  SirenPlayerView(art: .constant(.voice), onCarMode: {})
}
