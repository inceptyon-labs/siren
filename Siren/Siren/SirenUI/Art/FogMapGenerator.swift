import CoreGraphics
import CryptoKit
import Foundation

/// Builds a book's map. A port of `design/prototypes/fogmap/gen.py` (square sheet, cartouche kept
/// clear): SHA-256 of the book ID seeds the terrain noise, coast, hills, forests, river, the road
/// and the chapter regions. Pure and deterministic; slow enough (tens of ms) to keep off the main thread.
nonisolated enum FogMapGenerator {
  static func generate(_ key: FogMap.Key) -> FogMap {
    var builder = Builder(key: key)
    return builder.build()
  }
}

nonisolated private struct Builder {
  let key: FogMap.Key
  let seed: UInt64
  let bounds: [Double]
  let nx = MapGrid.nx
  let ny = MapGrid.ny
  let w = MapGrid.sheet

  var h: [Double] = []
  var threshold = 0.0
  var land: [Bool] = []
  var seaD: [Double] = []
  var landD: [Double] = []
  var landHeights: [Double] = []
  var road: [CGPoint] = []
  var nearest: [Int32] = []
  var regions: [Int32] = []
  var busy: [Bool] = []
  /// Numerals' keep-out boxes: no hill or tree ink is laid under the lettering.
  var lettering: [CGRect] = []
  /// Each chapter's land points, away from the coast.
  var regionPoints: [[CGPoint]] = []

  init(key: FogMap.Key) {
    self.key = key
    seed = SHA256.hash(data: Data(key.bookID.utf8)).prefix(8).reduce(0) { $0 << 8 | UInt64($1) }
    var starts = key.chapterStarts.map { min(max($0.isFinite ? $0 : 0, 0), 1) }.sorted()
    if starts.isEmpty || starts[0] > 0 { starts.insert(0, at: 0) }
    starts[0] = 0
    bounds = starts + [1]
  }

  func rng(_ name: String) -> MapRandom { MapRandom("\(seed):\(name)") }

  func quantile(_ fraction: Double) -> Double {
    landHeights[min(landHeights.count - 1, Int(Double(landHeights.count) * fraction))]
  }

  func isLand(_ x: Double, _ y: Double) -> Bool { land[MapGrid.index(x, y)] }

  func chapter(at s: Double) -> Int32 {
    var lo = 0
    var hi = bounds.count
    while lo < hi {
      let mid = (lo + hi) / 2
      if s < bounds[mid] { hi = mid } else { lo = mid + 1 }
    }
    return Int32(min(bounds.count - 2, lo - 1))
  }

  mutating func build() -> FogMap {
    terrain()
    makeRoad()
    makeRegions()
    let rivers = makeRivers()
    let borders = MapGrid.borders(regions) { a, b in
      landD[MapGrid.index(a.x, a.y)] >= 1 && landD[MapGrid.index(b.x, b.y)] >= 1
    }
    let coast = MapGrid.march(h, level: threshold)
      .filter { $0.closed && $0.points.count > 5 }
      .map { MapGrid.simplify(MapGrid.chaikin($0.points, closed: true), closed: true, eps: 0.3) }
    let smoothSea = MapGrid.blur(seaD, passes: 2)
    let waterlines = [(1.5, 0.5), (2.9, 0.32), (4.6, 0.18)].map { level, opacity in
      FogMap.Waterline(
        opacity: opacity,
        lines: MapGrid.march(smoothSea, level: level)
          .filter { $0.points.count > 4 }
          .map { MapGrid.simplify(MapGrid.chaikin($0.points, closed: $0.closed), closed: $0.closed, eps: 0.3) }
      )
    }
    let highlands = MapGrid.march(h, level: quantile(0.8))
      .filter { $0.closed && $0.points.count > 5 }
      .map { MapGrid.simplify(MapGrid.chaikin($0.points, closed: true), closed: true, eps: 0.4) }

    busy = [Bool](repeating: false, count: nx * ny)
    let reserve = FogMap.cartouche
    let c = MapGrid.cell
    let o = MapGrid.origin
    for b in Int((reserve.minY - 6 - o) / c)...Int((reserve.maxY + 6 - o) / c) {
      for a in Int((reserve.minX - 6 - o) / c)...Int((reserve.maxX + 6 - o) / c) where a < nx && b < ny {
        busy[b * nx + a] = true
      }
    }
    for river in rivers {
      for p in stride(from: 0, to: river.count, by: 2) { mark(river[p], radius: 5) }
    }
    for p in stride(from: 0, to: road.count, by: 2) { mark(road[p], radius: 6) }

    let placed = placeNumerals()
    let hills = placeHills()
    let trees = placeTrees()
    let waves = placeWaves()
    let numerals = spares(for: placed, ink: hills.map(\.footprint) + trees.map(\.footprint))
    return FogMap(
      key: key,
      bounds: bounds,
      coast: coast,
      waterlines: waterlines,
      highlands: highlands,
      rivers: rivers,
      borders: borders,
      road: road,
      numerals: numerals,
      hills: hills,
      trees: trees,
      waves: waves,
      compass: compass(),
      cloud: cloud(),
      nearestRoad: nearest,
      regions: regions,
      edgeX: MapNoise("\(seed):fog-x"),
      edgeY: MapNoise("\(seed):fog-y")
    )
  }

  // MARK: Terrain

  private static func ellipse(
    _ x: Double,
    _ y: Double,
    _ cx: Double,
    _ cy: Double,
    _ rx: Double,
    _ ry: Double,
    _ rot: Double
  ) -> Double {
    let dx = x - cx
    let dy = y - cy
    let c = cos(rot)
    let s = sin(rot)
    let u = (dx * c + dy * s) / rx
    let v = (-dx * s + dy * c) / ry
    return 1 - (u * u + v * v)
  }

  /// Shaped value field (island, coast, twin isles or bay) plus domain-warped fbm, cut at a seeded land fraction.
  private mutating func terrain() {
    var r = rng("shape")
    let nz = MapNoise("\(seed):noise")
    let wz = MapNoise("\(seed):warp")
    let mode = Int(seed % 4)
    let cx = w * (0.5 + r.uniform(-0.07, 0.07))
    let cy = w * (0.5 + r.uniform(-0.07, 0.07))
    let rot = r.uniform(0, Double.pi)
    let rx = w * r.uniform(0.38, 0.46)
    let ry = w * r.uniform(0.36, 0.44)
    let w = self.w
    let base: (Double, Double) -> Double
    switch mode {
    case 0:
      base = { x, y in Self.ellipse(x, y, cx, cy, rx, ry, rot) }
    case 1:
      let a = r.uniform(0, 2 * Double.pi)
      let ux = cos(a)
      let uy = sin(a)
      base = { x, y in 1.25 * ((x - w / 2) * ux + (y - w / 2) * uy) / (w * 0.5) }
    case 2:
      let a = r.uniform(0, 2 * Double.pi)
      let off = r.uniform(0.2, 0.26)
      let c1 = (w / 2 + cos(a) * w * off, w / 2 + sin(a) * w * off)
      let c2 = (w / 2 - cos(a) * w * off, w / 2 - sin(a) * w * off)
      let r1 = r.uniform(0.3, 0.36)
      let r2 = r.uniform(0.26, 0.32)
      base = { x, y in
        max(
          Self.ellipse(x, y, c1.0, c1.1, w * r1, w * r1 * 1.15, rot),
          Self.ellipse(x, y, c2.0, c2.1, w * r2, w * r2 * 1.15, rot + 1)
        )
      }
    default:
      let a = r.uniform(0, 2 * Double.pi)
      let bx = cx + cos(a) * rx * 0.8
      let by = cy + sin(a) * ry * 0.8
      let rb = min(rx, ry) * r.uniform(0.5, 0.62)
      base = { x, y in
        let d = hypot(x - bx, y - by) / rb
        return Self.ellipse(x, y, cx, cy, rx * 1.08, ry * 1.08, rot) - 1.4 * max(0, 1 - d * d)
      }
    }
    let ox = r.uniform(0, 300)
    let oy = r.uniform(0, 300)
    h = [Double](repeating: 0, count: nx * ny)
    for j in 0..<ny {
      let y = MapGrid.y(j)
      for i in 0..<nx {
        let x = MapGrid.x(i)
        let wx = wz.fbm(x / 150 + 7.1, y / 150, octaves: 3) * 46
        let wy = wz.fbm(x / 150, y / 150 + 3.3, octaves: 3) * 46
        h[j * nx + i] = base(x, y) + 0.95 * nz.fbm((x + wx) / 105 + ox, (y + wy) / 105 + oy, octaves: 5)
      }
    }
    let frac = [0.46, 0.54, 0.44, 0.44][mode] + r.uniform(-0.03, 0.03)
    let pad = MapGrid.pad
    var visible: [Double] = []
    for j in pad..<(ny - pad) {
      for i in pad..<(nx - pad) { visible.append(h[j * nx + i]) }
    }
    visible.sort()
    threshold = visible[Int(Double(visible.count) * (1 - frac))]
    for i in 0..<nx {
      h[i] = -9
      h[(ny - 1) * nx + i] = -9
    }
    for j in 0..<ny {
      h[j * nx] = -9
      h[j * nx + nx - 1] = -9
    }
    land = h.map { $0 > threshold }
    seaD = MapGrid.chamfer(land)
    landD = MapGrid.chamfer(land.map { !$0 })
    landHeights = []
    for j in pad..<(ny - pad) {
      for i in pad..<(nx - pad) where land[j * nx + i] { landHeights.append(h[j * nx + i]) }
    }
    landHeights.sort()
    if landHeights.isEmpty { landHeights = [threshold] }
  }

  // MARK: Road and regions

  private func cost(_ p: CGPoint, _ q: CGPoint) -> Double {
    var wet = 0
    for k in 1..<10 where !isLand(p.x + (q.x - p.x) * Double(k) / 10, p.y + (q.y - p.y) * Double(k) / 10) {
      wet += 1
    }
    return MapGrid.dist(p, q) * (1 + 0.9 * Double(wet))
  }

  /// Poisson waypoints on land, toured greedily then untangled with 2-opt (water crossings cost more).
  private mutating func makeRoad() {
    var r = rng("road")
    let mz = MapNoise("\(seed):meander")
    var candidates: [CGPoint] = []
    for j in 0..<ny {
      for i in 0..<nx {
        let x = MapGrid.x(i)
        let y = MapGrid.y(j)
        if landD[j * nx + i] >= 2.5 && 22 <= x && x <= w - 22 && 22 <= y && y <= w - 22 {
          candidates.append(CGPoint(x: x, y: y))
        }
      }
    }
    let rmin = sqrt(Double(landHeights.count) * MapGrid.cell * MapGrid.cell / 17) * 0.82
    r.shuffle(&candidates)
    let reserve = FogMap.cartouche.insetBy(dx: -8, dy: -8)
    var way: [CGPoint] = []
    for p in candidates where !reserve.contains(p) {
      if way.allSatisfy({ (p.x - $0.x) * (p.x - $0.x) + (p.y - $0.y) * (p.y - $0.y) >= rmin * rmin }) {
        way.append(p)
      }
    }
    if way.isEmpty {
      let deepest = landD.indices.max { landD[$0] < landD[$1] } ?? 0
      way = [CGPoint(x: MapGrid.x(deepest % nx), y: MapGrid.y(deepest / nx))]
    }
    let a = r.uniform(0, 2 * Double.pi)
    let ux = cos(a)
    let uy = sin(a)
    var start = way[0]
    for p in way where p.x * ux + p.y * uy < start.x * ux + start.y * uy { start = p }

    var path = [start]
    var rest = way.filter { $0 != start }
    while !rest.isEmpty {
      let last = path[path.count - 1]
      var bestIndex = 0
      var bestCost = cost(last, rest[0])
      for k in 1..<rest.count {
        let c = cost(last, rest[k])
        if c < bestCost {
          bestCost = c
          bestIndex = k
        }
      }
      path.append(rest.remove(at: bestIndex))
    }
    var improved = true
    while improved {
      improved = false
      let n = path.count
      for i in stride(from: 0, to: n - 2, by: 1) {
        for k in (i + 2)..<n {
          let pa = path[i]
          let pb = path[i + 1]
          let pc = path[k]
          let delta: Double
          if k + 1 < n {
            delta = cost(pa, pc) + cost(pb, path[k + 1]) - cost(pa, pb) - cost(pc, path[k + 1])
          } else {
            delta = cost(pa, pc) - cost(pa, pb)
          }
          if delta < -1e-6 {
            path[(i + 1)...k].reverse()
            improved = true
          }
        }
      }
    }
    let curve = MapGrid.resample(MapGrid.catmull(path), step: 2)
    var meander: [CGPoint] = []
    for (k, p) in curve.enumerated() {
      let a0 = curve[max(k - 1, 0)]
      let a1 = curve[min(k + 1, curve.count - 1)]
      let dx = a1.x - a0.x
      let dy = a1.y - a0.y
      var l = hypot(dx, dy)
      if l == 0 { l = 1 }
      let off = 6 * mz.fbm(Double(k) * 2.0 / 34, 3.7, octaves: 3)
      meander.append(CGPoint(x: p.x - dy / l * off, y: p.y + dx / l * off))
    }
    road = MapGrid.resample(meander, step: 2)
  }

  /// Every grid point belongs to the chapter of its nearest (every other) road point.
  /// Grid points are searched in blocks: only road points that can be nearest to some point of a block are tried.
  private mutating func makeRegions() {
    let last = Double(road.count - 1)
    let sub = Array(stride(from: 0, to: road.count, by: 2))
    let chapters = sub.map { chapter(at: Double($0) / last) }
    let xs = sub.map { Double(road[$0].x) }
    let ys = sub.map { Double(road[$0].y) }
    nearest = [Int32](repeating: 0, count: nx * ny)
    regions = [Int32](repeating: 0, count: nx * ny)
    let block = 6
    let reach = Double(block - 1) * MapGrid.cell * 0.5 * 2.squareRoot()
    var candidates: [Int] = []
    for j0 in stride(from: 0, to: ny, by: block) {
      for i0 in stride(from: 0, to: nx, by: block) {
        let i1 = min(i0 + block, nx) - 1
        let j1 = min(j0 + block, ny) - 1
        let cx = (MapGrid.x(i0) + MapGrid.x(i1)) / 2
        let cy = (MapGrid.y(j0) + MapGrid.y(j1)) / 2
        var dmin = Double.infinity
        for s in xs.indices {
          dmin = min(dmin, hypot(xs[s] - cx, ys[s] - cy))
        }
        let limit = (dmin + 2 * reach) * (dmin + 2 * reach)
        candidates.removeAll(keepingCapacity: true)
        for s in xs.indices where (xs[s] - cx) * (xs[s] - cx) + (ys[s] - cy) * (ys[s] - cy) <= limit {
          candidates.append(s)
        }
        for j in j0...j1 {
          let y = MapGrid.y(j)
          for i in i0...i1 {
            let x = MapGrid.x(i)
            var best = candidates[0]
            var bestD = Double.infinity
            for s in candidates {
              let dx = xs[s] - x
              let dy = ys[s] - y
              let d = dx * dx + dy * dy
              if d < bestD {
                bestD = d
                best = s
              }
            }
            nearest[j * nx + i] = Int32(sub[best])
            regions[j * nx + i] = chapters[best]
          }
        }
      }
    }
  }

  // MARK: Rivers

  private func makeRivers() -> [[CGPoint]] {
    var r = rng("river")
    let hi = quantile(0.86)
    let pad = MapGrid.pad
    var sources: [(Int, Int)] = []
    for j in (pad + 4)..<(ny - pad - 4) {
      for i in (pad + 4)..<(nx - pad - 4) where land[j * nx + i] && h[j * nx + i] > hi {
        sources.append((i, j))
      }
    }
    r.shuffle(&sources)
    var out: [[CGPoint]] = []
    for (i, j) in sources.prefix(60) {
      if out.count >= 2 { break }
      let source = CGPoint(x: MapGrid.x(i), y: MapGrid.y(j))
      if out.contains(where: { MapGrid.dist(source, $0[0]) < 70 }) { continue }
      var path = [(i, j)]
      var seen: Set<Int> = [j * nx + i]
      while land[path[path.count - 1].1 * nx + path[path.count - 1].0] && path.count < 300 {
        let (ci, cj) = path[path.count - 1]
        var best: (Int, Int)?
        var bestCost = 0.0
        for a in -1...1 {
          for b in -1...1 where a != 0 || b != 0 {
            let qi = ci + a
            let qj = cj + b
            guard !seen.contains(qj * nx + qi), 0 < qi, qi < nx - 1, 0 < qj, qj < ny - 1 else { continue }
            let c = h[qj * nx + qi] + 0.014 * landD[qj * nx + qi] + r.uniform(0, 0.006)
            if best == nil || c < bestCost {
              best = (qi, qj)
              bestCost = c
            }
          }
        }
        guard let next = best else { break }
        seen.insert(next.1 * nx + next.0)
        path.append(next)
      }
      let end = path[path.count - 1]
      if land[end.1 * nx + end.0] || path.count < 14 { continue }
      let points = path.map { CGPoint(x: MapGrid.x($0.0), y: MapGrid.y($0.1)) }
      out.append(MapGrid.simplify(MapGrid.chaikin(points, closed: false, iterations: 3), closed: false, eps: 0.25))
    }
    return out
  }

  // MARK: Decoration

  private mutating func mark(_ p: CGPoint, radius: Double) {
    let k = MapGrid.index(p.x, p.y)
    let ci = k % nx
    let cj = k / nx
    let rr = Int(radius / MapGrid.cell) + 1
    for a in (ci - rr)...(ci + rr) where a >= 0 && a < nx {
      for b in (cj - rr)...(cj + rr) where b >= 0 && b < ny {
        let dx = MapGrid.x(a) - p.x
        let dy = MapGrid.y(b) - p.y
        if dx * dx + dy * dy <= radius * radius { busy[b * nx + a] = true }
      }
    }
  }

  private func free(_ p: CGPoint) -> Bool { !busy[MapGrid.index(p.x, p.y)] }

  private func clearOfLettering(_ ink: CGRect) -> Bool { !lettering.contains { $0.intersects(ink) } }

  /// Poisson-disc pick from `input`: free cells only, and only where `ink` (the glyph's extent there) misses the lettering.
  private func poisson(
    _ input: [CGPoint],
    rmin: Double,
    rng: inout MapRandom,
    max: Int,
    ink: (CGPoint) -> CGRect
  ) -> [CGPoint] {
    var candidates = input
    rng.shuffle(&candidates)
    var accepted: [CGPoint] = []
    var grid: [Int: [CGPoint]] = [:]
    func cell(_ gi: Int, _ gj: Int) -> Int { (gi + 4096) * 8192 + gj + 4096 }
    for p in candidates where free(p) && clearOfLettering(ink(p)) {
      let gi = Int((p.x / rmin).rounded(.down))
      let gj = Int((p.y / rmin).rounded(.down))
      var clear = true
      outer: for a in (gi - 1)...(gi + 1) {
        for b in (gj - 1)...(gj + 1) {
          for q in grid[cell(a, b)] ?? [] where (q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y) < rmin * rmin {
            clear = false
            break outer
          }
        }
      }
      guard clear else { continue }
      accepted.append(p)
      grid[cell(gi, gj), default: []].append(p)
      if accepted.count >= max { break }
    }
    return accepted
  }

  /// Every chapter big enough gets a numeral near the middle of its region, off the road.
  private mutating func placeNumerals() -> [FogMap.Numeral] {
    var cells = [[CGPoint]](repeating: [], count: bounds.count - 1)
    for j in 0..<ny {
      for i in 0..<nx where landD[j * nx + i] >= 1.5 {
        cells[Int(regions[j * nx + i])].append(CGPoint(x: MapGrid.x(i), y: MapGrid.y(j)))
      }
    }
    regionPoints = cells
    let roadSample = stride(from: 0, to: road.count, by: 3).map { road[$0] }
    var boxes = [FogMap.cartouche.insetBy(dx: -6, dy: -6)]
    var out: [FogMap.Numeral] = []
    for (chapter, points) in cells.enumerated() where points.count >= 8 {
      let cx = points.reduce(0) { $0 + $1.x } / Double(points.count)
      let cy = points.reduce(0) { $0 + $1.y } / Double(points.count)
      let width = Double(MapGrid.roman(chapter + 1).count) * 6 + 4
      let reach = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        .insetBy(dx: -width / 2 - 2, dy: -12)
      let nearby = roadSample.filter { reach.contains($0) }
      var best: (score: Double, point: CGPoint, box: CGRect)?
      for p in points {
        let box = CGRect(x: p.x - width / 2, y: p.y - 8, width: width, height: 10)
        if box.minX < 16 || box.maxX > w - 16 || box.minY < 16 || box.maxY > w - 16 { continue }
        let spaced = box.insetBy(dx: -4, dy: -2)
        if boxes.contains(where: { $0.intersects(spaced) }) { continue }
        let wide = box.insetBy(dx: -2, dy: -2)
        var onRoad = 0
        for q in nearby where wide.minX < q.x && q.x < wide.maxX && wide.minY < q.y && q.y < wide.maxY {
          onRoad += 1
        }
        let score = hypot(p.x - cx, p.y - cy) * 0.3 + 20 * Double(onRoad)
        if best == nil || score < best!.score { best = (score, p, box) }
      }
      guard let best else { continue }
      boxes.append(best.box)
      mark(CGPoint(x: best.point.x, y: best.point.y - 3), radius: 9)
      let numeral = FogMap.Numeral(chapter: chapter + 1, point: best.point)
      lettering.append(FogMap.keepOut(numeral))
      out.append(numeral)
    }
    return out
  }

  /// Up to six clear spots per numeral in its own region, nearest first and spaced apart: off the road and the
  /// other numerals, with no hill or tree ink (`ink`) under the lettering.
  private func spares(for numerals: [FogMap.Numeral], ink: [CGRect]) -> [FogMap.Numeral] {
    let roadSample = stride(from: 0, to: road.count, by: 3).map { road[$0] }
    let boxes = numerals.map(FogMap.numeralBox)
    let reserve = FogMap.cartouche.insetBy(dx: -6, dy: -6)
    return numerals.enumerated().map { index, numeral in
      let p0 = numeral.point
      let box = boxes[index]
      let room = FogMap.keepOut(numeral)
      let reach = 40.0
      let area = box.insetBy(dx: -reach - 4, dy: -reach - 4)
      let nearInk = ink.filter { $0.intersects(area) }
      let nearRoad = roadSample.filter { area.contains($0) }
      let others = boxes.enumerated().filter { $0.offset != index && $0.element.intersects(area) }.map(\.element)
      let candidates = regionPoints[numeral.chapter - 1]
        .map { (point: $0, d: hypot($0.x - p0.x, $0.y - p0.y)) }
        .filter { $0.d >= 10 && $0.d <= reach }
        .sorted { $0.d < $1.d }
      var out: [CGPoint] = []
      for (p, _) in candidates {
        let dx = p.x - p0.x
        let dy = p.y - p0.y
        let moved = box.offsetBy(dx: dx, dy: dy)
        if moved.minX < 16 || moved.maxX > w - 16 || moved.minY < 16 || moved.maxY > w - 16 { continue }
        let spaced = moved.insetBy(dx: -4, dy: -2)
        if spaced.intersects(reserve) || others.contains(where: { $0.intersects(spaced) }) { continue }
        let wide = moved.insetBy(dx: -2, dy: -2)
        if nearRoad.contains(where: { wide.contains($0) }) { continue }
        let clearing = room.offsetBy(dx: dx, dy: dy)
        if nearInk.contains(where: { $0.intersects(clearing) }) { continue }
        if out.contains(where: { hypot($0.x - p.x, $0.y - p.y) < 10 }) { continue }
        out.append(p)
        if out.count == 6 { break }
      }
      return FogMap.Numeral(chapter: numeral.chapter, point: p0, spares: out)
    }
  }

  private mutating func placeHills() -> [FogMap.Hill] {
    var r = rng("hills-player")
    let hi = quantile(0.66)
    let mountain = quantile(0.9)
    var candidates: [CGPoint] = []
    for j in 0..<ny {
      for i in 0..<nx {
        let k = j * nx + i
        let x = MapGrid.x(i)
        let y = MapGrid.y(j)
        if land[k] && h[k] > hi && landD[k] >= 2 && 12 < x && x < w - 12 && 18 < y && y < w - 10 {
          let jx = x + r.uniform(-1.5, 1.5)
          candidates.append(CGPoint(x: jx, y: y + r.uniform(-1.5, 1.5)))
        }
      }
    }
    // A hill's width is drawn after it's picked, so test the widest it can be.
    let widest = { [h] (p: CGPoint) -> CGRect in
      let peak = h[MapGrid.index(p.x, p.y)] > mountain
      return FogMap.Hill(base: p, width: peak ? 20 : 16, mountain: peak).footprint
    }
    var out: [FogMap.Hill] = []
    for p in poisson(candidates, rmin: 15, rng: &r, max: 40, ink: widest).sorted(by: { $0.y < $1.y }) {
      let peak = h[MapGrid.index(p.x, p.y)] > mountain
      let width = peak ? 13 + 7 * r.random() : 10 + 6 * r.random()
      let height = width * (peak ? 0.95 : 0.48)
      out.append(FogMap.Hill(base: p, width: width, mountain: peak))
      mark(CGPoint(x: p.x, y: p.y - height / 2), radius: width * 0.7)
    }
    return out
  }

  private mutating func placeTrees() -> [FogMap.Tree] {
    let fz = MapNoise("\(seed):forest")
    var r = rng("trees-player")
    let hi = quantile(0.66)
    var candidates: [CGPoint] = []
    for j in 0..<ny {
      for i in 0..<nx {
        let k = j * nx + i
        let x = MapGrid.x(i) + r.uniform(-1.7, 1.7)
        let y = MapGrid.y(j) + r.uniform(-1.7, 1.7)
        if land[k] && landD[k] >= 1.5 && h[k] < hi && 10 < x && x < w - 10 && 14 < y && y < w - 10
          && fz.fbm(x / 62, y / 62, octaves: 3) > 0.12
        {
          candidates.append(CGPoint(x: x, y: y))
        }
      }
    }
    let tree = { (p: CGPoint) in FogMap.Tree(base: p, conifer: fz.n(p.x / 9, p.y / 9) > 0.05) }
    return poisson(candidates, rmin: 5.2, rng: &r, max: 500) { tree($0).footprint }
      .sorted { $0.y < $1.y }
      .map(tree)
  }

  private mutating func placeWaves() -> [CGPoint] {
    var r = rng("waves-player")
    var candidates: [CGPoint] = []
    for j in 0..<ny {
      for i in 0..<nx {
        let x = MapGrid.x(i)
        let y = MapGrid.y(j)
        if seaD[j * nx + i] > 6 && 24 < x && x < w - 24 && 24 < y && y < w - 20 {
          candidates.append(CGPoint(x: x, y: y))
        }
      }
    }
    let waves = poisson(candidates, rmin: 42, rng: &r, max: 9) { _ in .null }
    for p in waves { mark(p, radius: 6) }
    return waves
  }

  /// The corner with the most open sea, away from the cartouche.
  private func compass() -> CGPoint {
    let r = 15.0
    let reserve = FogMap.cartouche
    let corners = [
      CGPoint(x: 36 + r, y: 36 + r), CGPoint(x: w - 36 - r, y: 36 + r),
      CGPoint(x: 36 + r, y: w - 30 - r), CGPoint(x: w - 36 - r, y: w - 30 - r),
    ]
    .filter {
      !(reserve.minX - r - 8 < $0.x && $0.x < reserve.maxX + r + 8 && reserve.minY - r - 8 < $0.y
        && $0.y < reserve.maxY + r + 8)
    }
    var best = corners[0]
    var bestSea = -1
    for corner in corners {
      var sea = 0
      for a in -3...3 {
        for b in -3...3 where !isLand(corner.x + Double(a) * r / 3, corner.y + Double(b) * r / 3) { sea += 1 }
      }
      if sea > bestSea {
        bestSea = sea
        best = corner
      }
    }
    return best
  }

  /// SVG `feTurbulence` (.012 × .019, 4 octaves) as the fog's lighter cloud, alpha = 2.7 × noise − 1.
  private func cloud() -> [UInt8] {
    let noise = MapNoise("\(seed):cloud")
    let side = FogMap.cloudSide
    let span = w + 2 * FogMap.cloudMargin
    var out = [UInt8](repeating: 0, count: side * side)
    for py in 0..<side {
      let y = -FogMap.cloudMargin + (Double(py) + 0.5) * span / Double(side)
      for px in 0..<side {
        let x = -FogMap.cloudMargin + (Double(px) + 0.5) * span / Double(side)
        let alpha = 2.7 * noise.turbulence(x * 0.012, y * 0.019, octaves: 4) - 1
        out[py * side + px] = UInt8(min(max(alpha, 0), 1) * 255)
      }
    }
    return out
  }
}
