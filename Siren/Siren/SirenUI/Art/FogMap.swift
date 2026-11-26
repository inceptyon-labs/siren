import CoreGraphics
import Foundation

/// One book's ink map, built by `FogMapGenerator` from the book ID and its chapter starts.
/// Everything is in map units on a 400 × 400 sheet; views scale it to their size.
nonisolated struct FogMap: Sendable {
  struct Key: Hashable, Sendable {
    let bookID: String
    let chapterStarts: [Double]
  }

  struct Waterline: Sendable {
    let opacity: Double
    let lines: [[CGPoint]]
  }

  struct Hill: Sendable {
    let base: CGPoint
    let width: Double
    let mountain: Bool

    /// The inked extent, base to peak, stroke included.
    var footprint: CGRect {
      let height = width * (mountain ? 0.95 : 0.48)
      return CGRect(x: base.x - width / 2, y: base.y - height, width: width, height: height).insetBy(dx: -0.5, dy: -0.5)
    }
  }

  struct Tree: Sendable {
    let base: CGPoint
    let conifer: Bool

    /// The inked extent, crown to trunk foot, stroke included (glyph scale 2.4 as drawn by the sheet).
    var footprint: CGRect {
      let crown = conifer ? 6.24 : 4.8
      let trunk = conifer ? 1.2 : 1.68
      return CGRect(x: base.x - 2.4, y: base.y - crown, width: 4.8, height: crown + trunk).insetBy(dx: -0.4, dy: -0.4)
    }
  }

  struct Numeral: Sendable {
    let chapter: Int
    let point: CGPoint
    /// Clear ground in the same region, nearest first, for when a flag or the marker covers `point`.
    var spares: [CGPoint] = []
  }

  static let sheet = MapGrid.sheet
  /// The cover cartouche's box, top right (114 × 124 pt on a 354 pt map, 12 pt in from the corner).
  static let cartouche = CGRect(x: 228, y: 12, width: 114, height: 124)
    .applying(CGAffineTransform(scaleX: sheet / 354, y: sheet / 354))
  /// The fog's cloud texture covers the sheet plus this margin on every side.
  static let cloudMargin = 24.0
  static let cloudSide = 160

  let key: Key
  /// Chapter boundaries as fractions of the book: 0, each later chapter's start, 1.
  let bounds: [Double]
  let coast: [[CGPoint]]
  let waterlines: [Waterline]
  let highlands: [[CGPoint]]
  let rivers: [[CGPoint]]
  let borders: [[CGPoint]]
  /// The route, evenly spaced; index `k` is `k / (road.count - 1)` of the way through the book.
  let road: [CGPoint]
  /// Where each chapter's numeral goes; chapters too small for one have none.
  let numerals: [Numeral]
  let hills: [Hill]
  let trees: [Tree]
  let waves: [CGPoint]
  let compass: CGPoint
  /// Alpha of the fog's cloud texture, `cloudSide` squared.
  let cloud: [UInt8]
  /// Per grid point: index of the nearest route point, and that point's chapter (0-based).
  let nearestRoad: [Int32]
  let regions: [Int32]
  let edgeX: MapNoise
  let edgeY: MapNoise

  var chapterCount: Int { bounds.count - 1 }

  /// Progress quantised to the route: -1 before the start, `road.count` once finished.
  func step(at progress: Double) -> Int {
    if progress <= 0 { return -1 }
    if progress >= 1 { return road.count }
    return Int((progress * Double(road.count - 1)).rounded(.toNearestOrEven))
  }

  func point(at progress: Double) -> CGPoint {
    road[min(max(step(at: progress), 0), road.count - 1)]
  }

  /// 1-based chapter at a fraction of the book.
  func chapter(at progress: Double) -> Int {
    var lo = 0
    var hi = bounds.count
    while lo < hi {
      let mid = (lo + hi) / 2
      if progress < bounds[mid] { hi = mid } else { lo = mid + 1 }
    }
    return max(1, min(chapterCount, lo))
  }

  /// The charted ground, marker, flags and current chapter's lettering for one step of the route.
  func reveal(_ key: FogMapReveal.Key) -> FogMapReveal {
    let flags = key.flags.map { point(at: $0) }
    guard key.step >= 0 else {
      return FogMapReveal(key: key, charted: [], fogged: true, marker: nil, flags: flags, numerals: [], label: nil)
    }
    guard key.step < road.count else {
      let numerals = clear(numerals, of: flags, marker: nil)
      return FogMapReveal(
        key: key,
        charted: [],
        fogged: false,
        marker: nil,
        flags: flags,
        numerals: numerals,
        label: nil
      )
    }
    let nx = MapGrid.nx
    let ny = MapGrid.ny
    let marker = road[key.step]
    var heard = [Bool](repeating: false, count: nx * ny)
    var field = [Double](repeating: 0, count: nx * ny)
    for j in 0..<ny {
      for i in 0..<nx {
        let k = j * nx + i
        let x = MapGrid.x(i) - marker.x
        let y = MapGrid.y(j) - marker.y
        heard[k] = Int(nearestRoad[k]) < key.step || hypot(x, y) < 24
        if heard[k] && i > 0 && j > 0 && i < nx - 1 && j < ny - 1 { field[k] = 1 }
      }
    }
    let charted = MapGrid.march(field, level: 0.5)
      .filter { $0.closed && $0.points.count > 4 }
      .map { roughen(MapGrid.simplify(MapGrid.chaikin($0.points, closed: true), closed: true, eps: 0.3)) }
    let label = labelAnchor(key: key, heard: heard, marker: marker, flags: flags)
    let lettered = clear(numerals.filter { $0.chapter < key.chapter }, of: flags, marker: marker)
    return FogMapReveal(
      key: key,
      charted: charted,
      fogged: true,
      marker: marker,
      flags: flags,
      numerals: lettered,
      label: label
    )
  }

  private static func flagBox(_ p: CGPoint) -> CGRect { CGRect(x: p.x - 3, y: p.y - 17, width: 14, height: 19) }

  static func numeralBox(_ numeral: Numeral) -> CGRect {
    let width = Double(MapGrid.roman(numeral.chapter).count) * 6 + 4
    return CGRect(x: numeral.point.x - width / 2, y: numeral.point.y - 8, width: width, height: 10)
  }

  /// Advance of each numeral letter in New York 10, tracked 1.2, as the progress layer letters them.
  private static let numeralAdvances: [Character: Double] = ["I": 4.83, "V": 8.38, "X": 8.16, "L": 7.19, "C": 8.43]

  /// Ground a numeral keeps clear of hills and trees: its ink (cap height 7.05) plus the paper halo and a little air.
  /// The text is centered on its whole advance, so the trailing tracking leaves the ink 0.6 left of the point.
  static func keepOut(_ numeral: Numeral) -> CGRect {
    let advance = MapGrid.roman(numeral.chapter).reduce(0) { $0 + (numeralAdvances[$1] ?? 8.4) }
    let air = 2.7
    return CGRect(
      x: numeral.point.x - advance / 2 - air,
      y: numeral.point.y - 7.05 - air,
      width: advance - 1.2 + 2 * air,
      height: 7.05 + 2 * air
    )
  }

  /// Numerals are placed when the map is built, before any flags exist; move the ones a flag or the marker covers
  /// to their nearest free spare, else nudge them aside, onto clear ground when one of the moves has it.
  private func clear(_ numerals: [Numeral], of flags: [CGPoint], marker: CGPoint?) -> [Numeral] {
    var taken = flags.map(Self.flagBox)
    if let marker { taken.append(CGRect(x: marker.x - 9, y: marker.y - 9, width: 18, height: 18)) }
    let others = numerals.map(Self.numeralBox)
    let moves = [(0.0, -14.0), (0, 14), (-16, 0), (16, 0), (-16, -14), (16, -14), (-16, 14), (16, 14)]
    let ground = hills.map(\.footprint) + trees.map(\.footprint)
    return numerals.enumerated().map { index, numeral in
      let box = others[index]
      guard taken.contains(where: { $0.intersects(box) }) else { return numeral }
      for spare in numeral.spares {
        let moved = box.offsetBy(dx: spare.x - numeral.point.x, dy: spare.y - numeral.point.y)
        if !taken.contains(where: { $0.intersects(moved) }) { return Numeral(chapter: numeral.chapter, point: spare) }
      }
      var fallback: Numeral?
      for (dx, dy) in moves {
        let moved = box.offsetBy(dx: dx, dy: dy)
        let blocked =
          taken.contains { $0.intersects(moved) }
          || others.enumerated().contains { $0.offset != index && $0.element.intersects(moved) }
          || moved.intersects(Self.cartouche) || moved.minX < 12 || moved.maxX > Self.sheet - 12
          || moved.minY < 12 || moved.maxY > Self.sheet - 12
        if blocked { continue }
        let nudged = Numeral(chapter: numeral.chapter, point: CGPoint(x: numeral.point.x + dx, y: numeral.point.y + dy))
        let room = Self.keepOut(nudged)
        if !ground.contains(where: { $0.intersects(room) }) { return nudged }
        if fallback == nil { fallback = nudged }
      }
      return fallback ?? numeral
    }
  }

  /// The fog's ragged edge: the outline pushed about by fractal noise (SVG `feDisplacementMap`, scale 22).
  private func roughen(_ ring: [CGPoint]) -> [CGPoint] {
    MapGrid.resample(ring, step: 2.5).map { p in
      let dx = 22 * (edgeX.turbulence(p.x * 0.03, p.y * 0.03, octaves: 3) - 0.5)
      let dy = 22 * (edgeY.turbulence(p.x * 0.03, p.y * 0.03, octaves: 3) - 0.5)
      return CGPoint(x: p.x - dx, y: p.y - dy)
    }
  }

  /// The current chapter is lettered on the fog just past the marker, clear of the charted ground.
  private func labelAnchor(key: FogMapReveal.Key, heard: [Bool], marker: CGPoint, flags: [CGPoint]) -> CGPoint? {
    let nx = MapGrid.nx
    let ny = MapGrid.ny
    let w = Self.sheet
    var near = [Bool](repeating: false, count: nx * ny)
    let disk = (-5...5).flatMap { a in (-5...5).compactMap { b in a * a + b * b <= 25 ? (a, b) : nil } }
    for j in 0..<ny {
      for i in 0..<nx where heard[j * nx + i] {
        for (a, b) in disk {
          let ii = i + a
          let jj = j + b
          if ii >= 0 && jj >= 0 && ii < nx && jj < ny { near[jj * nx + ii] = true }
        }
      }
    }
    func fogged(_ x: Double, _ y: Double) -> Bool { !near[MapGrid.index(x, y)] }

    var boxes = [Self.cartouche.insetBy(dx: -6, dy: -6)]
    boxes += flags.map(Self.flagBox)
    boxes.append(CGRect(x: marker.x - 15, y: marker.y - 15, width: 30, height: 30))
    let chapter = Int32(key.chapter - 1)
    let fs = 12.5
    let width = max(Double(FogMapReveal.lettering(key.chapterTitle).count) * fs * 0.46, 30)
    let height = fs * 2.1
    var best: (score: Double, point: CGPoint)?
    for j in 0..<ny {
      for i in 0..<nx {
        let x = MapGrid.x(i)
        let y = MapGrid.y(j)
        let d = hypot(x - marker.x, y - marker.y)
        guard d < 120 else { continue }
        let x0 = x - width / 2
        let y0 = y - height * 0.62
        let x1 = x + width / 2
        let y1 = y + height * 0.38
        if x0 < 14 || x1 > w - 14 || y0 < 14 || y1 > w - 14 { continue }
        let e = 9.0
        let samples = [
          (x0, y0), (x1, y0), (x0, y1), (x1, y1), (x, y0), (x, y1),
          (x0 - e, y0 - e), (x1 + e, y0 - e), (x0 - e, y1 + e), (x1 + e, y1 + e),
          (x, y0 - e), (x, y1 + e), (x0 - e, y), (x1 + e, y),
        ]
        var dark = Double(samples.filter { !fogged($0.0, $0.1) }.count)
        if regions[MapGrid.index(x, y)] != chapter { dark += 0.4 }
        let box = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
        let occupied = Double(boxes.filter { $0.intersects(box) }.count)
        let score = d * 0.35 + 400 * occupied + 160 * dark
        if best == nil || score < best!.score { best = (score, CGPoint(x: x, y: y)) }
      }
    }
    return best?.point
  }
}

/// What moves with listening: charted ground, the marker, flags and the current chapter's label.
/// It changes only when progress moves to the next route step (about 1/600 of the book).
nonisolated struct FogMapReveal: Sendable, Equatable {
  struct Key: Hashable, Sendable {
    var step: Int
    var flags: [Double]
    var chapter: Int
    var chapterTitle: String
  }

  let key: Key
  /// Charted ground as even-odd rings, edge already roughened.
  let charted: [[CGPoint]]
  /// False once the book is finished.
  let fogged: Bool
  let marker: CGPoint?
  let flags: [CGPoint]
  /// Numerals of the charted chapters, moved off any flag.
  let numerals: [FogMap.Numeral]
  /// Center of the current chapter's lettering on the fog.
  let label: CGPoint?

  static func == (a: Self, b: Self) -> Bool { a.key == b.key }

  /// The chapter title as lettered on the fog; long titles are cut so they fit the sheet.
  static func lettering(_ title: String) -> String {
    title.count > 30 ? title.prefix(29).trimmingCharacters(in: .whitespaces) + "…" : title
  }
}
