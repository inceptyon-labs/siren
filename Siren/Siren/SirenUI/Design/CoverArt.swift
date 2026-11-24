import CoreImage
import SwiftUI
import UIKit

// Demo covers are drawn in SwiftUI so the review build needs no server. In the real app the colour
// image comes from Audiobookshelf and the sketch is made from it by `SketchFilter`.

enum CoverLayout: Hashable { case saltRoad, sunSea, mountains, tree, moonHills, tower, ship, waves }

struct CoverPalette: Hashable {
  let sky: UInt32, sun: UInt32, mid: UInt32, deep: UInt32, title: UInt32, byline: UInt32

  static let slateSea = CoverPalette(
    sky: 0xC9D6DF,
    sun: 0xF2B33D,
    mid: 0x3B5B73,
    deep: 0x22384A,
    title: 0x1E2C38,
    byline: 0x3B5B73
  )
  static let midnight = CoverPalette(
    sky: 0x1D2A44,
    sun: 0xF4C95D,
    mid: 0x3C5A8C,
    deep: 0x0F1830,
    title: 0xF4EEDD,
    byline: 0xF4C95D
  )
  static let orchard = CoverPalette(
    sky: 0xF1E3C4,
    sun: 0xC8402B,
    mid: 0x4F7A4A,
    deep: 0x8B6A3E,
    title: 0x3A2A1A,
    byline: 0x8B6A3E
  )
  static let ember = CoverPalette(
    sky: 0x1E1A1A,
    sun: 0xE4572E,
    mid: 0x6B2A1F,
    deep: 0x3A1712,
    title: 0xF2E6D8,
    byline: 0xF2A33A
  )
  static let dusk = CoverPalette(
    sky: 0x2E2440,
    sun: 0xF1D9A0,
    mid: 0x5B3F6B,
    deep: 0x8E5A7A,
    title: 0xF1D9A0,
    byline: 0xE8B9C6
  )
  static let rose = CoverPalette(
    sky: 0xF3D5CF,
    sun: 0xB23A48,
    mid: 0x6B4F7A,
    deep: 0x3A2E46,
    title: 0x3A2E46,
    byline: 0x8A3A48
  )
  static let forest = CoverPalette(
    sky: 0xDCE6D2,
    sun: 0xE0703A,
    mid: 0x3F6B4F,
    deep: 0x2A4A38,
    title: 0x20352A,
    byline: 0x3F6B4F
  )
}

struct CoverSpec: Hashable {
  var layout: CoverLayout
  var palette: CoverPalette
  var title: String
  var author: String

  static let saltRoad = CoverSpec(
    layout: .saltRoad,
    palette: .slateSea,
    title: "The Salt Road",
    author: "Mara Kessling"
  )
}

/// The full-colour jacket, drawn on a 100 x 100 grid.
struct CoverArtwork: View {
  let spec: CoverSpec

  var body: some View {
    Canvas { ctx, size in
      let s = size.width / 100
      func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
        CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
      }
      func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }
      let p = spec.palette

      let titleColor = spec.layout == .saltRoad ? Color(sirenHex: 0x163F45) : Color(sirenHex: p.title)
      let bylineColor = spec.layout == .saltRoad ? Color(sirenHex: 0x7A3A20) : Color(sirenHex: p.byline)
      let unbounded = CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
      func titleLine(_ text: String, _ points: Double) -> GraphicsContext.ResolvedText {
        ctx.resolve(
          Text(text)
            .font(.system(size: points * s, weight: .semibold, design: .serif))
            .tracking(0.4 * s)
            .foregroundColor(titleColor)
        )
      }
      func wrap(_ points: Double) -> [String] {
        var lines: [String] = []
        for word in spec.title.uppercased().split(separator: " ").map(String.init) {
          if let last = lines.last, titleLine(last + " " + word, points).measure(in: unbounded).width <= 84 * s {
            lines[lines.count - 1] = last + " " + word
          } else {
            lines.append(word)
          }
        }
        return lines
      }
      // Largest size that keeps the title to two lines.
      let titlePoints = [9.8, 8.6, 7.4, 6.6].first { wrap($0).count <= 2 } ?? 6.6
      let lines = wrap(titlePoints)
      let byline = ctx.resolve(
        Text(spec.author.uppercased())
          .font(.system(size: 5.2 * s, weight: .semibold))
          .tracking(1.5 * s)
          .foregroundColor(bylineColor)
      )
      let lineHeights = lines.map { titleLine($0, titlePoints).measure(in: unbounded).height * 0.92 }
      let blockBottom = 9 + (lineHeights.reduce(0, +) + byline.measure(in: unbounded).height) / s + 2.5
      let artOffset = max(0, blockBottom + 2 - 31)

      let background = spec.layout == .saltRoad ? 0xEAD3A0 : p.sky
      ctx.fill(Path(rect(0, 0, 100, 100)), with: .color(Color(sirenHex: background)))
      var art = ctx
      art.translateBy(x: 0, y: artOffset * s)
      func fill(_ path: Path, _ hex: UInt32) { art.fill(path, with: .color(Color(sirenHex: hex))) }

      switch spec.layout {
      case .saltRoad:
        fill(Path(rect(0, 0, 100, 100)), 0xEAD3A0)
        fill(Path(ellipseIn: rect(51, 35, 30, 30)), 0xC0522B)
        fill(Path(rect(0, 50, 100, 50)), 0x1E6971)
        fill(Path(rect(0, 50, 100, 5)), 0x2C7C83)
        for r in [
          (52.0, 53.4, 9.0, 1.6), (68, 53.4, 11, 1.6), (55, 58.6, 5, 1.5), (70, 58.6, 7, 1.5), (73, 64, 3, 1.4),
        ] {
          fill(Path(rect(r.0, r.1, r.2, r.3)), 0xE39A66)
        }
        var left = Path()
        left.move(to: pt(0, 79))
        left.addCurve(to: pt(37, 87), control1: pt(13, 76), control2: pt(25, 78))
        left.addLines([pt(34, 100), pt(0, 100)])
        fill(left, 0xD6AE6E)
        var right = Path()
        right.move(to: pt(100, 75))
        right.addCurve(to: pt(60, 87), control1: pt(86, 75), control2: pt(72, 79))
        right.addLines([pt(63, 100), pt(100, 100)])
        fill(right, 0xC2914F)
        var road = Path()
        road.addLines([pt(28, 100), pt(63.5, 50.5), pt(64.5, 50.5), pt(58, 100)])
        fill(road, 0xF4EAD2)
        var dash = Path()
        dash.move(to: pt(43, 100))
        dash.addLine(to: pt(64, 50.5))
        art.stroke(
          dash,
          with: .color(Color(sirenHex: 0xC0522B)),
          style: StrokeStyle(lineWidth: 0.8 * s, dash: [2.4 * s, 2.4 * s])
        )

      case .sunSea:
        fill(Path(rect(0, 0, 100, 100)), p.sky)
        fill(Path(ellipseIn: rect(30, 40, 40, 40)), p.sun)
        fill(Path(rect(0, 62, 100, 38)), p.mid)
        for i in 0..<5 { fill(Path(rect(18 + Double(i) * 3, 68 + Double(i) * 6, 64 - Double(i) * 6, 1.6)), p.sun) }

      case .mountains:
        fill(Path(rect(0, 0, 100, 100)), p.sky)
        fill(Path(ellipseIn: rect(62, 34, 16, 16)), p.sun)
        var back = Path()
        back.addLines([pt(0, 78), pt(28, 46), pt(46, 66), pt(68, 40), pt(100, 74), pt(100, 100), pt(0, 100)])
        fill(back, p.mid)
        var front = Path()
        front.addLines([pt(0, 88), pt(22, 70), pt(40, 84), pt(62, 64), pt(100, 90), pt(100, 100), pt(0, 100)])
        fill(front, p.deep)

      case .tree:
        fill(Path(rect(0, 0, 100, 100)), p.sky)
        fill(Path(rect(0, 82, 100, 18)), p.deep)
        fill(Path(rect(47, 58, 6, 26)), p.deep)
        fill(Path(ellipseIn: rect(26, 34, 48, 36)), p.mid)
        for c in [(36.0, 46.0), (52, 40), (60, 54), (44, 58), (30, 54)] {
          fill(Path(ellipseIn: rect(c.0, c.1, 5, 5)), p.sun)
        }

      case .moonHills:
        fill(Path(rect(0, 0, 100, 100)), p.sky)
        fill(Path(ellipseIn: rect(56, 34, 22, 22)), p.sun)
        fill(Path(ellipseIn: rect(62, 31, 20, 20)), p.sky)
        var hill = Path()
        hill.move(to: pt(0, 76))
        hill.addCurve(to: pt(100, 70), control1: pt(30, 58), control2: pt(66, 86))
        hill.addLines([pt(100, 100), pt(0, 100)])
        fill(hill, p.mid)
        var low = Path()
        low.move(to: pt(0, 90))
        low.addCurve(to: pt(100, 84), control1: pt(40, 78), control2: pt(70, 96))
        low.addLines([pt(100, 100), pt(0, 100)])
        fill(low, p.deep)
        fill(Path(rect(30, 80, 3, 8)), p.sun)

      case .tower:
        fill(Path(rect(0, 0, 100, 100)), p.sky)
        fill(Path(rect(0, 74, 100, 26)), p.mid)
        var tower = Path()
        tower.addLines([pt(44, 80), pt(47, 44), pt(53, 44), pt(56, 80)])
        fill(tower, p.deep)
        fill(Path(rect(45.5, 38, 9, 6)), p.sun)
        var roof = Path()
        roof.addLines([pt(44, 38), pt(50, 31), pt(56, 38)])
        fill(roof, p.deep)
        var beam = Path()
        beam.addLines([pt(55, 40), pt(100, 30), pt(100, 46)])
        art.fill(beam, with: .color(Color(sirenHex: p.sun).opacity(0.45)))

      case .ship:
        fill(Path(rect(0, 0, 100, 100)), p.sky)
        fill(Path(ellipseIn: rect(66, 32, 14, 14)), p.sun)
        fill(Path(rect(0, 70, 100, 30)), p.deep)
        var hull = Path()
        hull.addLines([pt(30, 68), pt(70, 68), pt(64, 76), pt(36, 76)])
        fill(hull, p.mid)
        var sail = Path()
        sail.addLines([pt(50, 40), pt(50, 66), pt(34, 66)])
        fill(sail, p.title)
        var sail2 = Path()
        sail2.addLines([pt(52, 44), pt(52, 66), pt(64, 66)])
        fill(sail2, p.sun)

      case .waves:
        fill(Path(rect(0, 0, 100, 100)), p.sky)
        for i in 0..<4 {
          let y = 52 + Double(i) * 12
          var wave = Path()
          wave.move(to: pt(0, y))
          for k in 0..<5 {
            let x = Double(k) * 20
            wave.addQuadCurve(to: pt(x + 20, y), control: pt(x + 10, y - 7))
          }
          wave.addLines([pt(100, 100), pt(0, 100)])
          fill(wave, i % 2 == 0 ? p.mid : p.deep)
        }
      }

      var y = 9 * s
      for (line, height) in zip(lines, lineHeights) {
        ctx.draw(titleLine(line, titlePoints), at: CGPoint(x: 50 * s, y: y), anchor: .top)
        y += height
      }
      ctx.draw(byline, at: CGPoint(x: 50 * s, y: y + 2.5 * s), anchor: .top)
    }
    .aspectRatio(1, contentMode: .fit)
  }
}

/// Graphite pencil sketch of any cover image, made on the device with Core Image and Core Graphics.
/// Every layer sits on opaque paper, so the sketch looks the same on light and dark screens.
enum SketchFilter {
  private static let context = CIContext(options: [.cacheIntermediates: false])
  static let paperColor = CIColor(red: 236 / 255, green: 234 / 255, blue: 228 / 255)
  private static let graphite = CIColor(red: 0.33, green: 0.345, blue: 0.37)

  static func sketch(_ image: UIImage) -> UIImage? {
    guard let cg = image.cgImage else { return nil }
    let input = CIImage(cgImage: cg)
    let extent = input.extent
    let mono = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
    let paper = CIImage(color: paperColor).cropped(to: extent)

    // Tone: how dark each region is. Mid-tones get one hatch layer, the darkest get a second.
    let darkness = mono.applyingFilter("CIColorInvert")
    let midMask =
      darkness
      .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 1.6, kCIInputBrightnessKey: -0.18])
      .applyingFilter("CIColorClamp")
    let deepMask =
      darkness
      .applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 2.6, kCIInputBrightnessKey: -0.5])
      .applyingFilter("CIColorClamp")

    let size = extent.size
    let light = CIImage(cgImage: hatchTexture(size: size, angle: .pi / 4, spacing: size.width / 70, seed: 11))
    let cross = CIImage(cgImage: hatchTexture(size: size, angle: -.pi / 3.2, spacing: size.width / 58, seed: 29))

    let shaded = light.composited(over: paper)
      .applyingFilter(
        "CIBlendWithMask",
        parameters: [kCIInputBackgroundImageKey: paper, kCIInputMaskImageKey: midMask]
      )
    let crossed = cross.composited(over: shaded)
      .applyingFilter(
        "CIBlendWithMask",
        parameters: [kCIInputBackgroundImageKey: shaded, kCIInputMaskImageKey: deepMask]
      )

    // Outlines: one clean line per colour boundary.
    let edges =
      input
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.6]).cropped(to: extent)
      .applyingFilter("CIMorphologyGradient", parameters: [kCIInputRadiusKey: max(1.2, size.width / 400)])
      .applyingFilter("CIMaximumComponent")
      .applyingFilter(
        "CIColorMatrix",
        parameters: [
          "inputRVector": CIVector(x: 7, y: 0, z: 0, w: 0),
          "inputGVector": CIVector(x: 0, y: 7, z: 0, w: 0),
          "inputBVector": CIVector(x: 0, y: 0, z: 7, w: 0),
          "inputBiasVector": CIVector(x: -0.5, y: -0.5, z: -0.5, w: 0),
        ]
      )
      .applyingFilter("CIColorClamp")
      .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.6])
      .cropped(to: extent)
    let pencil = CIImage(color: graphite).cropped(to: extent)
    let result = pencil.applyingFilter(
      "CIBlendWithMask",
      parameters: [kCIInputBackgroundImageKey: crossed, kCIInputMaskImageKey: edges]
    )

    guard let out = context.createCGImage(result, from: extent) else { return nil }
    return UIImage(cgImage: out, scale: image.scale, orientation: .up)
  }

  private static var textures: [String: CGImage] = [:]

  /// Loose pencil hatching: broken strokes with varied weight, spacing and pressure.
  private static func hatchTexture(size: CGSize, angle: CGFloat, spacing: CGFloat, seed: UInt64) -> CGImage {
    let key = "\(Int(size.width))x\(Int(size.height))-\(angle)-\(seed)"
    if let hit = textures[key] { return hit }
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false
    let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
      let cg = context.cgContext
      var rng = SeededRandom(seed: seed)
      let diagonal = hypot(size.width, size.height)
      cg.translateBy(x: size.width / 2, y: size.height / 2)
      cg.rotate(by: angle)
      cg.setLineCap(.round)
      var y = -diagonal / 2
      while y < diagonal / 2 {
        var x = -diagonal / 2
        while x < diagonal / 2 {
          let length = spacing * CGFloat(3 + rng.next() * 9)
          let drift = CGFloat(rng.next() - 0.5) * spacing * 0.35
          cg.setLineWidth(CGFloat(0.8 + rng.next() * 1.1) * size.width / 600)
          cg.setStrokeColor(
            UIColor(red: 0.33, green: 0.345, blue: 0.37, alpha: CGFloat(0.28 + rng.next() * 0.32)).cgColor
          )
          cg.move(to: CGPoint(x: x, y: y))
          cg.addLine(to: CGPoint(x: x + length, y: y + drift))
          cg.strokePath()
          x += length + spacing * CGFloat(0.3 + rng.next() * 1.4)
        }
        y += spacing * CGFloat(0.75 + rng.next() * 0.6)
      }
    }
    let cgImage = image.cgImage!
    textures[key] = cgImage
    return cgImage
  }
}

@MainActor
final class CoverStore {
  static let shared = CoverStore()
  private var cache: [CoverSpec: (color: UIImage, sketch: UIImage)] = [:]

  func images(for spec: CoverSpec) -> (color: UIImage, sketch: UIImage) {
    if let hit = cache[spec] { return hit }
    let renderer = ImageRenderer(content: CoverArtwork(spec: spec).frame(width: 300, height: 300))
    renderer.scale = 2
    let color = renderer.uiImage ?? UIImage()
    let sketch = SketchFilter.sketch(color) ?? color
    cache[spec] = (color, sketch)
    return (color, sketch)
  }
}

/// The left part of the cover is inked in up to `progress`; the rest is the pencil sketch.
struct BrushedRevealMask: Shape {
  var progress: Double
  var seed: Int

  func path(in rect: CGRect) -> Path {
    var path = Path()
    guard progress > 0 else { return path }
    guard progress < 1 else { return Path(rect) }
    let baseX = rect.minX + rect.width * progress
    let amp = rect.width * 0.018
    let steps = 90
    var generator = SeededRandom(seed: UInt64(truncatingIfNeeded: seed))
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    for i in 0...steps {
      let t = Double(i) / Double(steps)
      let y = rect.minY + rect.height * t
      let wave = sin(t * 9 + Double(seed % 7)) * 0.6 + sin(t * 23 + Double(seed % 5)) * 0.3
      let bristle = generator.next() * 0.9 - 0.45
      path.addLine(to: CGPoint(x: baseX + amp * (wave + bristle), y: y))
    }
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

struct SeededRandom {
  private var state: UInt64
  init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
  mutating func next() -> Double {
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Double((state >> 33) % 10_000) / 10_000
  }
}

extension String {
  var sirenSeed: Int {
    unicodeScalars.reduce(5381) { ($0 &* 33 &+ Int($1.value)) & 0x7FFF_FFFF }
  }
}

/// A book's cover with its listening progress inked in.
struct RevealCover: View {
  let book: DemoBook
  var progress: Double?
  var showTicks = false
  var cornerRadius: CGFloat = SirenTheme.coverRadius
  var shadow = true

  var body: some View {
    let images = CoverStore.shared.images(for: book.cover)
    let p = progress ?? book.progress
    ZStack {
      Image(uiImage: images.sketch).resizable()
      Image(uiImage: images.color).resizable()
        .mask(BrushedRevealMask(progress: p, seed: book.id.sirenSeed))
      if showTicks {
        ChapterTicks(starts: book.chapterStarts, current: book.currentChapter, progress: p)
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(.black.opacity(0.08), lineWidth: 0.5)
    }
    .shadow(color: .black.opacity(shadow ? 0.18 : 0), radius: 4, y: 2)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(book.title) cover, \(Int((p * 100).rounded())) percent listened")
  }
}

struct ChapterTicks: View {
  let starts: [Double]
  let current: Int
  let progress: Double

  var body: some View {
    Canvas { ctx, size in
      for (i, start) in starts.enumerated() where i > 0 {
        let x = size.width * start
        let isCurrent = i + 1 == current
        let height: CGFloat = isCurrent ? 14 : 7
        let rect = CGRect(x: x - 0.5, y: size.height - height - 4, width: isCurrent ? 2 : 1, height: height)
        let heard = start <= progress
        ctx.fill(
          Path(rect),
          with: .color(heard ? .white.opacity(isCurrent ? 0.95 : 0.7) : SirenTheme.graphite.opacity(0.6))
        )
      }
    }
    .allowsHitTesting(false)
  }
}
