import SwiftUI

/// A book's hand-inked map: heard chapters charted, the rest under fog, bookmarks as red flags,
/// the cover in a cartouche. The linework is one Canvas that never redraws for progress; only the
/// progress layer (fog, marker, flags, numerals) redraws, and only when `reveal` moves a route step.
struct FogMapView<Cover: View>: View {
  let map: FogMap
  let reveal: FogMapReveal
  let title: String
  let author: String
  @ViewBuilder let cover: () -> Cover

  var body: some View {
    Color.clear
      .aspectRatio(1, contentMode: .fit)
      .overlay {
        GeometryReader { geo in
          let unit = geo.size.width / 354
          ZStack(alignment: .topLeading) {
            FogMapSheet(map: map).equatable()
            FogMapProgressLayer(map: map, reveal: reveal).equatable()
            FogMapCartouche(title: title, author: author, unit: unit, cover: cover())
              .offset(x: 228 * unit, y: 12 * unit)
          }
        }
      }
      .clipped()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(accessibilityText)
  }

  private var accessibilityText: String {
    let count = map.chapterCount
    let current = min(max(reveal.key.chapter, 1), count)
    if !reveal.fogged {
      return count == 1 ? "Map of \(title), charted" : "Map of \(title), all \(count) chapters charted"
    }
    if reveal.key.step < 0 {
      return count == 1 ? "Map of \(title), under fog" : "Map of \(title), all \(count) chapters under fog"
    }
    var parts: [String] = []
    if current > 1 {
      parts.append(current == 2 ? "chapter 1 charted" : "chapters 1 to \(current - 1) charted")
    }
    if current < count {
      parts.append(
        current + 1 == count ? "chapter \(count) under fog" : "chapters \(current + 1) to \(count) under fog"
      )
    }
    if parts.isEmpty { return "Map of \(title), partly charted" }
    return "Map of \(title), " + parts.joined(separator: ", ")
  }
}

/// Map colours from the prototype.
enum FogInk {
  static let ink = Color(sirenHex: 0x2B2620)
  static let paper = Color(sirenHex: 0xE9E1CF)
  static let sea = Color(sirenHex: 0x3E6B8C)
  static let flag = Color(sirenHex: 0xC8402B)
  static let fog = Color(sirenHex: 0x1C1F24)
  static let haze = Color(sirenHex: 0x2A2D35)
  static let card = Color(sirenHex: 0xF2EBDA)
}

/// Paper grain, stains and the fog's cloud as small bitmaps (SVG `feTurbulence` stand-ins).
nonisolated enum FogMapTextures {
  /// Dark speckle, tiling every 100 map units at 3 px per unit.
  static let grain: CGImage = {
    let noise = MapNoise("fogmap-grain")
    let side = 300
    let alpha = (0..<(side * side)).map { k -> Double in
      let x = (Double(k % side) + 0.5) / 3
      let y = (Double(k / side) + 0.5) / 3
      return 0.9 * noise.turbulence(x * 0.8, y * 0.8, octaves: 2, period: 80) - 0.4
    }
    return image(side: side, red: 0.17, green: 0.15, blue: 0.12, alpha: alpha)
  }()

  /// Brown foxing across the whole sheet.
  static let stains: CGImage = {
    let noise = MapNoise("fogmap-stains")
    let side = 160
    let span = MapGrid.sheet / Double(side)
    let alpha = (0..<(side * side)).map { k -> Double in
      let x = (Double(k % side) + 0.5) * span
      let y = (Double(k / side) + 0.5) * span
      return 0.9 * noise.turbulence(x * 0.013, y * 0.013, octaves: 3) - 0.38
    }
    return image(side: side, red: 0.5, green: 0.36, blue: 0.2, alpha: alpha)
  }()

  static func cloud(_ map: FogMap) -> CGImage {
    image(side: FogMap.cloudSide, red: 0.165, green: 0.176, blue: 0.208, alpha: map.cloud.map { Double($0) / 255 })
  }

  private static func image(side: Int, red: Double, green: Double, blue: Double, alpha: [Double]) -> CGImage {
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    for (k, value) in alpha.enumerated() {
      let a = min(max(value, 0), 1)
      pixels[k * 4] = UInt8(red * a * 255)
      pixels[k * 4 + 1] = UInt8(green * a * 255)
      pixels[k * 4 + 2] = UInt8(blue * a * 255)
      pixels[k * 4 + 3] = UInt8(a * 255)
    }
    return CGImage(
      width: side,
      height: side,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: side * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: CGDataProvider(data: Data(pixels) as CFData)!,
      decode: nil,
      shouldInterpolate: true,
      intent: .defaultIntent
    )!
  }
}

extension Path {
  fileprivate init(lines: [[CGPoint]], closed: Bool) {
    self.init()
    for line in lines where line.count > 1 {
      addLines(line)
      if closed { closeSubpath() }
    }
  }
}

extension GraphicsContext {
  /// Text centred on `point.x` with its baseline on `point.y`, optionally with a paper halo.
  fileprivate func draw(
    baseline point: CGPoint,
    color: Color,
    halo: Color? = nil,
    haloWidth: CGFloat = 0,
    _ text: (Color) -> Text
  ) {
    let resolved = resolve(text(color))
    let size = resolved.measure(in: CGSize(width: 2000, height: 2000))
    let top = CGPoint(x: point.x, y: point.y - resolved.firstBaseline(in: size))
    if let halo {
      let backing = resolve(text(halo))
      for k in 0..<12 {
        let angle = Double(k) * .pi / 6
        for radius in [haloWidth, haloWidth * 0.55] {
          draw(backing, at: CGPoint(x: top.x + cos(angle) * radius, y: top.y + sin(angle) * radius), anchor: .top)
        }
      }
    }
    draw(resolved, at: top, anchor: .top)
  }
}

/// Everything that doesn't move: sea, coast, hills, forests, river, chapter borders, road, compass, neatline.
private struct FogMapSheet: View, Equatable {
  let map: FogMap

  static func == (a: Self, b: Self) -> Bool { a.map.key == b.map.key }

  /// "/" hatching every 2.3 units, clipped to whatever it shades.
  private static let hatch: Path = {
    var path = Path()
    let step = 2.3 * 2.squareRoot()
    var c = 0.0
    while c <= 830 {
      path.move(to: CGPoint(x: c + 10, y: -10))
      path.addLine(to: CGPoint(x: -10, y: c + 10))
      c += step
    }
    return path
  }()

  var body: some View {
    Canvas { context, size in
      let scale = size.width / FogMap.sheet
      var ctx = context
      ctx.scaleBy(x: scale, y: scale)
      draw(in: &ctx)
      let r = 15.0
      context.draw(baseline: CGPoint(x: map.compass.x * scale, y: (map.compass.y - r - 3) * scale), color: FogInk.ink) {
        Text("N").font(.system(size: 10 * scale, design: .serif)).foregroundStyle($0)
      }
    }
  }

  private func draw(in ctx: inout GraphicsContext) {
    let sheet = CGRect(x: 0, y: 0, width: FogMap.sheet, height: FogMap.sheet)
    ctx.clip(to: Path(sheet))
    ctx.fill(Path(sheet), with: .color(FogInk.paper))
    ctx.fill(Path(sheet), with: .color(FogInk.sea.opacity(0.26)))
    let coast = Path(lines: map.coast, closed: true)
    ctx.drawLayer { wash in
      wash.addFilter(.blur(radius: 2.6))
      wash.stroke(coast, with: .color(FogInk.sea.opacity(0.32)), lineWidth: 9)
    }
    for waterline in map.waterlines {
      ctx.stroke(
        Path(lines: waterline.lines, closed: false),
        with: .color(FogInk.ink.opacity(waterline.opacity)),
        lineWidth: 0.7
      )
    }
    ctx.fill(coast, with: .color(FogInk.paper), style: FillStyle(eoFill: true))
    var highlands = ctx
    highlands.clip(to: Path(lines: map.highlands, closed: true))
    highlands.stroke(Self.hatch, with: .color(FogInk.ink.opacity(0.42)), lineWidth: 0.75)

    ctx.draw(Image(decorative: FogMapTextures.stains, scale: 1).interpolation(.high), in: sheet)
    ctx.fill(
      Path(sheet),
      with: .tiledImage(Image(decorative: FogMapTextures.grain, scale: 1), scale: 100 / 300)
    )
    ctx.stroke(coast, with: .color(FogInk.ink), style: StrokeStyle(lineWidth: 1.25, lineJoin: .round))

    for river in map.rivers {
      let n = river.count
      let parts = [river[0...(n / 3)], river[(n / 3)...(2 * n / 3)], river[(2 * n / 3)...]]
      for (part, width) in zip(parts, [0.7, 1.05, 1.45]) {
        ctx.stroke(
          Path(lines: [Array(part)], closed: false),
          with: .color(FogInk.ink),
          style: StrokeStyle(lineWidth: width, lineCap: .round)
        )
      }
    }
    ctx.stroke(
      Path(lines: map.borders, closed: false),
      with: .color(FogInk.ink.opacity(0.62)),
      style: StrokeStyle(lineWidth: 0.75, dash: [3, 2.6])
    )
    ctx.stroke(
      Path(lines: [map.road], closed: false),
      with: .color(FogInk.ink),
      style: StrokeStyle(lineWidth: 1.9, lineCap: .round, dash: [0, 4.4])
    )
    drawHills(in: &ctx)
    drawTrees(in: &ctx)
    drawWaves(in: &ctx)
    drawCompass(in: &ctx)
    drawNeatline(in: &ctx)
  }

  private func drawHills(in ctx: inout GraphicsContext) {
    for hill in map.hills {
      let x = hill.base.x
      let y = hill.base.y
      let w = hill.width
      var outline = Path()
      var shade = Path()
      if hill.mountain {
        let hh = w * 0.95
        outline.addLines([
          CGPoint(x: x - w / 2, y: y), CGPoint(x: x - w * 0.06, y: y - hh),
          CGPoint(x: x + w * 0.1, y: y - hh * 0.86), CGPoint(x: x + w / 2, y: y),
        ])
        shade.addLines([
          CGPoint(x: x - w * 0.06, y: y - hh), CGPoint(x: x + w * 0.1, y: y - hh * 0.86),
          CGPoint(x: x + w / 2, y: y), CGPoint(x: x + w * 0.1, y: y),
        ])
      } else {
        let hh = w * 0.48
        outline.move(to: CGPoint(x: x - w / 2, y: y))
        outline.addCurve(
          to: CGPoint(x: x, y: y - hh),
          control1: CGPoint(x: x - w * 0.38, y: y - hh * 0.75),
          control2: CGPoint(x: x - w * 0.2, y: y - hh)
        )
        outline.addCurve(
          to: CGPoint(x: x + w / 2, y: y),
          control1: CGPoint(x: x + w * 0.22, y: y - hh),
          control2: CGPoint(x: x + w * 0.4, y: y - hh * 0.6)
        )
        shade.move(to: CGPoint(x: x, y: y - hh))
        shade.addCurve(
          to: CGPoint(x: x + w / 2, y: y),
          control1: CGPoint(x: x + w * 0.22, y: y - hh),
          control2: CGPoint(x: x + w * 0.4, y: y - hh * 0.6)
        )
        shade.addLine(to: CGPoint(x: x + w * 0.14, y: y))
        shade.addCurve(
          to: CGPoint(x: x, y: y - hh),
          control1: CGPoint(x: x + w * 0.16, y: y - hh * 0.5),
          control2: CGPoint(x: x + w * 0.08, y: y - hh * 0.85)
        )
      }
      shade.closeSubpath()
      var body = outline
      body.closeSubpath()
      ctx.fill(body, with: .color(FogInk.paper))
      var shading = ctx
      shading.clip(to: shade)
      shading.stroke(Self.hatch, with: .color(FogInk.ink), lineWidth: 0.75)
      ctx.stroke(outline, with: .color(FogInk.ink), style: StrokeStyle(lineWidth: 0.95, lineJoin: .round))
    }
  }

  private func drawTrees(in ctx: inout GraphicsContext) {
    let s = 2.4
    var trees = Path()
    for tree in map.trees {
      let x = tree.base.x
      let y = tree.base.y
      if tree.conifer {
        trees.move(to: CGPoint(x: x, y: y - 2.6 * s))
        trees.addLine(to: CGPoint(x: x + s, y: y - 0.2 * s))
        trees.addLine(to: CGPoint(x: x - s, y: y - 0.2 * s))
        trees.closeSubpath()
        trees.move(to: CGPoint(x: x, y: y - 0.2 * s))
        trees.addLine(to: CGPoint(x: x, y: y + 0.5 * s))
      } else {
        trees.addEllipse(in: CGRect(x: x - s, y: y - 2 * s, width: 2 * s, height: 2 * s))
        trees.move(to: CGPoint(x: x, y: y))
        trees.addLine(to: CGPoint(x: x, y: y + 0.7 * s))
      }
    }
    ctx.fill(trees, with: .color(FogInk.paper))
    ctx.stroke(trees, with: .color(FogInk.ink), style: StrokeStyle(lineWidth: 0.7, lineJoin: .round))
  }

  private func drawWaves(in ctx: inout GraphicsContext) {
    let u = 2.6
    var waves = Path()
    for p in map.waves {
      waves.move(to: CGPoint(x: p.x - 1.5 * u, y: p.y))
      waves.addQuadCurve(to: CGPoint(x: p.x - 0.5 * u, y: p.y), control: CGPoint(x: p.x - u, y: p.y - 0.7 * u))
      waves.addQuadCurve(to: CGPoint(x: p.x + 0.5 * u, y: p.y), control: CGPoint(x: p.x, y: p.y + 0.7 * u))
      waves.addQuadCurve(to: CGPoint(x: p.x + 1.5 * u, y: p.y), control: CGPoint(x: p.x + u, y: p.y - 0.7 * u))
    }
    ctx.stroke(waves, with: .color(FogInk.ink.opacity(0.6)), style: StrokeStyle(lineWidth: 0.75, lineCap: .round))
  }

  private func drawCompass(in ctx: inout GraphicsContext) {
    let c = map.compass
    let r = 15.0
    ctx.fill(
      Path(ellipseIn: CGRect(x: c.x - r * 0.6, y: c.y - r * 0.6, width: r * 1.2, height: r * 1.2)),
      with: .color(FogInk.paper)
    )
    ctx.stroke(
      Path(ellipseIn: CGRect(x: c.x - r * 0.6, y: c.y - r * 0.6, width: r * 1.2, height: r * 1.2)),
      with: .color(FogInk.ink),
      lineWidth: 0.6
    )
    var points = Path()
    var dark = Path()
    for a in 0..<8 {
      let angle = Double(a) * .pi / 4 - .pi / 2
      let length = a % 2 == 0 ? r : r * 0.55
      let wv = r * 0.14
      let tip = CGPoint(x: c.x + cos(angle) * length, y: c.y + sin(angle) * length)
      let l1 = CGPoint(x: c.x + cos(angle - .pi / 2) * wv, y: c.y + sin(angle - .pi / 2) * wv)
      let l2 = CGPoint(x: c.x + cos(angle + .pi / 2) * wv, y: c.y + sin(angle + .pi / 2) * wv)
      points.addLines([l1, tip, l2])
      dark.addLines([c, tip, l2])
      dark.closeSubpath()
    }
    points.closeSubpath()
    ctx.fill(points, with: .color(FogInk.paper))
    ctx.stroke(points, with: .color(FogInk.ink), style: StrokeStyle(lineWidth: 0.7, lineJoin: .round))
    ctx.fill(dark, with: .color(FogInk.ink))
  }

  private func drawNeatline(in ctx: inout GraphicsContext) {
    let w = FogMap.sheet
    var bars = Path()
    for x in stride(from: 9, to: Int(w) - 9, by: 24) where (x / 24) % 2 == 0 {
      let x2 = min(Double(x) + 24, w - 9)
      bars.addRect(CGRect(x: Double(x), y: 5, width: x2 - Double(x), height: 4))
      bars.addRect(CGRect(x: Double(x), y: w - 9, width: x2 - Double(x), height: 4))
    }
    for y in stride(from: 9, to: Int(w) - 9, by: 24) where (y / 24) % 2 == 1 {
      let y2 = min(Double(y) + 24, w - 9)
      bars.addRect(CGRect(x: 5, y: Double(y), width: 4, height: y2 - Double(y)))
      bars.addRect(CGRect(x: w - 9, y: Double(y), width: 4, height: y2 - Double(y)))
    }
    ctx.fill(bars, with: .color(FogInk.ink))
    var frame = Path(CGRect(x: 5, y: 5, width: w - 10, height: w - 10))
    frame.addRect(CGRect(x: 9, y: 9, width: w - 18, height: w - 18))
    ctx.stroke(frame, with: .color(FogInk.ink), lineWidth: 0.8)
  }
}

/// Numerals of charted chapters, flags, the marker, the fog and the current chapter's lettering.
private struct FogMapProgressLayer: View, Equatable {
  let map: FogMap
  let reveal: FogMapReveal

  /// The fog's soft edge needs room past the map so it doesn't fade at the frame.
  private static let bleed: CGFloat = 24

  static func == (a: Self, b: Self) -> Bool { a.map.key == b.map.key && a.reveal == b.reveal }

  var body: some View {
    Canvas { context, size in
      var ctx = context
      let side = size.width - 2 * Self.bleed
      let scale = side / FogMap.sheet
      ctx.translateBy(x: Self.bleed, y: Self.bleed)
      drawNumerals(in: ctx, scale: scale)
      var units = ctx
      units.scaleBy(x: scale, y: scale)
      drawFlags(in: &units)
      drawFog(in: &ctx, side: side, scale: scale)
      drawLabel(in: ctx, scale: scale)
    }
    .padding(-Self.bleed)
    .allowsHitTesting(false)
  }

  private func drawNumerals(in ctx: GraphicsContext, scale: CGFloat) {
    for numeral in reveal.numerals {
      ctx.draw(
        baseline: CGPoint(x: numeral.point.x * scale, y: numeral.point.y * scale),
        color: FogInk.ink,
        halo: FogInk.paper,
        haloWidth: 1.2 * scale
      ) {
        Text(MapGrid.roman(numeral.chapter))
          .font(.system(size: 10 * scale, design: .serif))
          .tracking(1.2 * scale)
          .foregroundStyle($0)
      }
    }
  }

  private func drawFlags(in ctx: inout GraphicsContext) {
    for p in reveal.flags {
      var pole = Path()
      pole.move(to: CGPoint(x: p.x, y: p.y + 1))
      pole.addLine(to: CGPoint(x: p.x, y: p.y - 16))
      ctx.stroke(pole, with: .color(FogInk.ink), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
      var pennant = Path()
      pennant.addLines([
        CGPoint(x: p.x + 0.5, y: p.y - 16), CGPoint(x: p.x + 11, y: p.y - 12.6), CGPoint(x: p.x + 0.5, y: p.y - 9.2),
      ])
      pennant.closeSubpath()
      ctx.fill(pennant, with: .color(FogInk.flag))
      ctx.stroke(pennant, with: .color(FogInk.ink), style: StrokeStyle(lineWidth: 0.7, lineJoin: .round))
      ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.6, y: p.y, width: 5.2, height: 2)), with: .color(FogInk.ink))
    }
    if let m = reveal.marker {
      let ring = Path(ellipseIn: CGRect(x: m.x - 6.5, y: m.y - 6.5, width: 13, height: 13))
      ctx.fill(ring, with: .color(FogInk.paper))
      ctx.stroke(ring, with: .color(FogInk.ink), lineWidth: 1.5)
      ctx.fill(Path(ellipseIn: CGRect(x: m.x - 2.7, y: m.y - 2.7, width: 5.4, height: 5.4)), with: .color(FogInk.flag))
    }
  }

  /// A dark haze that bleeds into the charted ground, then the fog proper with a tighter edge.
  private func drawFog(in ctx: inout GraphicsContext, side: CGFloat, scale: CGFloat) {
    guard reveal.fogged else { return }
    let area = Path(CGRect(x: -Self.bleed, y: -Self.bleed, width: side + 2 * Self.bleed, height: side + 2 * Self.bleed))
    let margin = FogMap.cloudMargin * scale
    let cloudRect = CGRect(x: -margin, y: -margin, width: side + 2 * margin, height: side + 2 * margin)
    let cloud = Image(decorative: FogMapTextures.cloud(map), scale: 1).interpolation(.high)
    let charted = Path(lines: reveal.charted, closed: true)
      .applying(CGAffineTransform(scaleX: scale, y: scale))
    guard !reveal.charted.isEmpty else {
      ctx.fill(area, with: .color(FogInk.fog))
      ctx.draw(cloud, in: cloudRect)
      return
    }
    ctx.drawLayer { haze in
      haze.fill(area, with: .color(FogInk.haze.opacity(0.7)))
      haze.blendMode = .destinationOut
      haze.addFilter(.blur(radius: 13 * scale))
      haze.fill(charted, with: .color(.black), style: FillStyle(eoFill: true))
    }
    ctx.drawLayer { fog in
      fog.fill(area, with: .color(FogInk.fog))
      fog.draw(cloud, in: cloudRect)
      fog.blendMode = .destinationOut
      fog.addFilter(.blur(radius: 4 * scale))
      fog.fill(charted, with: .color(.black), style: FillStyle(eoFill: true))
    }
  }

  private func drawLabel(in ctx: GraphicsContext, scale: CGFloat) {
    guard reveal.fogged, let label = reveal.label else { return }
    let fs = 12.5
    let top = (label.y - fs * 0.55) * scale
    ctx.draw(baseline: CGPoint(x: label.x * scale, y: top), color: FogInk.paper) {
      Text(MapGrid.roman(reveal.key.chapter))
        .font(.system(size: 10 * scale, design: .serif))
        .tracking(1.8 * scale)
        .foregroundStyle($0)
    }
    let title = FogMapReveal.lettering(reveal.key.chapterTitle)
    guard !title.isEmpty else { return }
    ctx.draw(baseline: CGPoint(x: label.x * scale, y: top + fs * 1.15 * scale), color: FogInk.paper) {
      Text(title).font(.system(size: 13.5 * scale, design: .serif).italic()).foregroundStyle($0)
    }
  }
}

/// The cover cartouche: a notched card with the jacket, title and author, in 114 × 124 units.
private struct FogMapCartouche<Cover: View>: View {
  let title: String
  let author: String
  let unit: CGFloat
  let cover: Cover

  var body: some View {
    let u = unit
    ZStack(alignment: .topLeading) {
      CartoucheShape(radius: 7, inset: 0)
        .fill(FogInk.card)
        .shadow(color: .black.opacity(0.5), radius: 4 * u, y: 3 * u)
      CartoucheShape(radius: 7, inset: 0)
        .stroke(FogInk.ink, lineWidth: 1.1 * u)
      CartoucheShape(radius: 10.5, inset: 3.5)
        .stroke(FogInk.ink, lineWidth: 0.6 * u)
      Canvas { context, _ in
        var ctx = context
        ctx.translateBy(x: 4 * u, y: 4 * u)
        for x in [0.0, 114] {
          for y in [0.0, 124] {
            ctx.fill(
              Path(ellipseIn: CGRect(x: (x - 1.7) * u, y: (y - 1.7) * u, width: 3.4 * u, height: 3.4 * u)),
              with: .color(FogInk.ink)
            )
          }
        }
        ctx.stroke(
          Path(CGRect(x: 23.5 * u, y: 8.5 * u, width: 67 * u, height: 67 * u)),
          with: .color(FogInk.ink),
          lineWidth: 0.7 * u
        )
        var rule = Path()
        rule.move(to: CGPoint(x: 34 * u, y: 99.5 * u))
        rule.addLine(to: CGPoint(x: 52 * u, y: 99.5 * u))
        rule.move(to: CGPoint(x: 62 * u, y: 99.5 * u))
        rule.addLine(to: CGPoint(x: 80 * u, y: 99.5 * u))
        ctx.stroke(rule, with: .color(FogInk.ink), lineWidth: 0.6 * u)
        var diamond = Path()
        diamond.addLines([
          CGPoint(x: 57 * u, y: 97 * u), CGPoint(x: 59.5 * u, y: 99.5 * u),
          CGPoint(x: 57 * u, y: 102 * u), CGPoint(x: 54.5 * u, y: 99.5 * u),
        ])
        diamond.closeSubpath()
        ctx.fill(diamond, with: .color(FogInk.ink))
        ctx.draw(baseline: CGPoint(x: 57 * u, y: 93 * u), color: FogInk.ink) {
          fitted(title, size: 15, italic: false, color: $0, ctx: ctx)
        }
        ctx.draw(baseline: CGPoint(x: 57 * u, y: 114 * u), color: FogInk.ink) {
          fitted(author, size: 11.5, italic: true, color: $0, ctx: ctx)
        }
      }
      .padding(-4 * u)
      cover
        .frame(width: 64 * u, height: 64 * u)
        .offset(x: 25 * u, y: 10 * u)
    }
    .frame(width: 114 * u, height: 124 * u, alignment: .topLeading)
  }

  /// Shrinks long titles to fit the card.
  private func fitted(_ string: String, size: CGFloat, italic: Bool, color: Color, ctx: GraphicsContext) -> Text {
    func text(_ points: CGFloat) -> Text {
      let font = Font.system(size: points, design: .serif)
      return Text(string).font(italic ? font.italic() : font).foregroundStyle(color)
    }
    let natural = ctx.resolve(text(size * unit)).measure(in: CGSize(width: 4000, height: 400)).width
    let room = 100 * unit
    return natural > room ? text(max(size * unit * room / natural, 7 * unit)) : text(size * unit)
  }
}

/// A card with concave (notched) corners of `radius`, its edges `inset` in from the frame.
private struct CartoucheShape: Shape {
  let radius: CGFloat
  let inset: CGFloat

  func path(in rect: CGRect) -> Path {
    let u = rect.width / 114
    let w = 114.0
    let h = 124.0
    let corners = [(0.0, 0.0), (w, 0.0), (w, h), (0.0, h)]
    let a = (radius * radius - inset * inset).squareRoot()
    var path = Path()
    for (k, corner) in corners.enumerated() {
      let sx: CGFloat = corner.0 == 0 ? 1 : -1
      let sy: CGFloat = corner.1 == 0 ? 1 : -1
      // Arc around the corner from the edge before it to the edge after it, bulging inward.
      let start: CGPoint
      let end: CGPoint
      if k % 2 == 0 {
        start = CGPoint(x: corner.0 + sx * inset, y: corner.1 + sy * a)
        end = CGPoint(x: corner.0 + sx * a, y: corner.1 + sy * inset)
      } else {
        start = CGPoint(x: corner.0 + sx * a, y: corner.1 + sy * inset)
        end = CGPoint(x: corner.0 + sx * inset, y: corner.1 + sy * a)
      }
      let from = atan2(start.y - corner.1, start.x - corner.0)
      var to = atan2(end.y - corner.1, end.x - corner.0)
      if abs(to - from) > .pi { to += to < from ? 2 * .pi : -2 * .pi }
      for step in 0...8 {
        let t = from + (to - from) * Double(step) / 8
        let p = CGPoint(x: (corner.0 + cos(t) * radius) * u, y: (corner.1 + sin(t) * radius) * u)
        if k == 0 && step == 0 { path.move(to: p) } else { path.addLine(to: p) }
      }
    }
    path.closeSubpath()
    return path
  }
}
