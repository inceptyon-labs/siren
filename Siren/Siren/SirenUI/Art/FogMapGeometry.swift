import CoreGraphics
import CryptoKit
import Foundation

/// Python's `random.Random(str)`: a Mersenne Twister seeded from the string and its SHA-512.
/// Same sequence as the prototype (`design/prototypes/fogmap/gen.py`), so a book draws the same map.
nonisolated struct MapRandom {
  private var state = [UInt32](repeating: 0, count: 624)
  private var index = 624

  init(_ seed: String) {
    let text = Array(seed.utf8)
    let bytes = text + Array(SHA512.hash(data: Data(text)))
    var key: [UInt32] = []
    var end = bytes.count
    while end > 0 {
      let start = max(0, end - 4)
      key.append(bytes[start..<end].reduce(0) { $0 << 8 | UInt32($1) })
      end = start
    }
    while key.count > 1 && key.last == 0 { key.removeLast() }
    self.seed(with: key)
  }

  private mutating func seed(with key: [UInt32]) {
    state[0] = 19_650_218
    for i in 1..<624 {
      state[i] = 1_812_433_253 &* (state[i - 1] ^ (state[i - 1] >> 30)) &+ UInt32(i)
    }
    var i = 1
    var j = 0
    for _ in 0..<max(624, key.count) {
      state[i] = (state[i] ^ ((state[i - 1] ^ (state[i - 1] >> 30)) &* 1_664_525)) &+ key[j] &+ UInt32(j)
      i += 1
      j += 1
      if i >= 624 {
        state[0] = state[623]
        i = 1
      }
      if j >= key.count { j = 0 }
    }
    for _ in 0..<623 {
      state[i] = (state[i] ^ ((state[i - 1] ^ (state[i - 1] >> 30)) &* 1_566_083_941)) &- UInt32(i)
      i += 1
      if i >= 624 {
        state[0] = state[623]
        i = 1
      }
    }
    state[0] = 0x8000_0000
    index = 624
  }

  private mutating func next32() -> UInt32 {
    if index >= 624 {
      for k in 0..<624 {
        let y = (state[k] & 0x8000_0000) | (state[(k + 1) % 624] & 0x7FFF_FFFF)
        state[k] = state[(k + 397) % 624] ^ (y >> 1) ^ (y & 1 == 0 ? 0 : 0x9908_B0DF)
      }
      index = 0
    }
    var y = state[index]
    index += 1
    y ^= y >> 11
    y ^= (y << 7) & 0x9D2C_5680
    y ^= (y << 15) & 0xEFC6_0000
    y ^= y >> 18
    return y
  }

  mutating func random() -> Double {
    let a = Double(next32() >> 5)
    let b = Double(next32() >> 6)
    return (a * 67_108_864 + b) * (1.0 / 9_007_199_254_740_992)
  }

  mutating func uniform(_ a: Double, _ b: Double) -> Double {
    a + (b - a) * random()
  }

  private mutating func below(_ n: Int) -> Int {
    let bits = UInt32(Int.bitWidth - n.leadingZeroBitCount)
    var r = Int(next32() >> (32 - bits))
    while r >= n { r = Int(next32() >> (32 - bits)) }
    return r
  }

  mutating func shuffle<T>(_ items: inout [T]) {
    var i = items.count - 1
    while i > 0 {
      items.swapAt(i, below(i + 1))
      i -= 1
    }
  }
}

/// Seeded 2D gradient (Perlin) noise.
nonisolated struct MapNoise: Sendable {
  private let perm: [Int]
  private let gx: [Double]
  private let gy: [Double]

  init(_ rng: inout MapRandom) {
    var p = Array(0..<256)
    rng.shuffle(&p)
    perm = p + p
    var gx: [Double] = []
    var gy: [Double] = []
    for _ in 0..<256 {
      let a = rng.random() * (2 * Double.pi)
      gx.append(cos(a))
      gy.append(sin(a))
    }
    self.gx = gx
    self.gy = gy
  }

  init(_ seed: String) {
    var rng = MapRandom(seed)
    self.init(&rng)
  }

  /// `period` (at most 256) wraps the lattice so the noise tiles.
  func n(_ x: Double, _ y: Double, period: Int = 256) -> Double {
    let fx = x.rounded(.down)
    let fy = y.rounded(.down)
    let xf = x - fx
    let yf = y - fy
    let x0 = (Int(fx) % period + period) % period
    let y0 = (Int(fy) % period + period) % period
    let x1 = (x0 + 1) % period
    let y1 = (y0 + 1) % period
    let u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
    let v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)
    let a = perm[perm[x0] + y0]
    let b = perm[perm[x1] + y0]
    let c = perm[perm[x0] + y1]
    let d = perm[perm[x1] + y1]
    let n00 = gx[a] * xf + gy[a] * yf
    let n10 = gx[b] * (xf - 1) + gy[b] * yf
    let n01 = gx[c] * xf + gy[c] * (yf - 1)
    let n11 = gx[d] * (xf - 1) + gy[d] * (yf - 1)
    let x1n = n00 + u * (n10 - n00)
    let x2n = n01 + u * (n11 - n01)
    return x1n + v * (x2n - x1n)
  }

  /// Octaves normalised to the first octave's range.
  func fbm(_ x: Double, _ y: Double, octaves: Int = 5) -> Double {
    var s = 0.0
    var a = 1.0
    var fr = 1.0
    var norm = 0.0
    for _ in 0..<octaves {
      s += a * n(x * fr, y * fr)
      norm += a
      a *= 0.5
      fr *= 2.0
    }
    return s / norm
  }

  /// SVG `feTurbulence type="fractalNoise"`: halving octaves, mapped to 0...1 around 0.5.
  /// With `period`, the first octave tiles every `period` units (later octaves at multiples).
  func turbulence(_ x: Double, _ y: Double, octaves: Int, period: Int? = nil) -> Double {
    var s = 0.0
    var a = 1.0
    var fr = 1
    for _ in 0..<octaves {
      s += a * n(x * Double(fr), y * Double(fr), period: period.map { $0 * fr } ?? 256)
      a *= 0.5
      fr *= 2
    }
    return (s + 1) / 2
  }
}

/// The noise grid the map is built on: the sheet plus a margin, one sample per `cell` map units.
nonisolated enum MapGrid {
  static let sheet = 400.0
  static let cell = 3.5
  static let pad = 6
  static let nx = Int((sheet / cell).rounded(.toNearestOrEven)) + 2 * pad + 1
  static let ny = nx
  static let origin = -Double(pad) * cell

  static func x(_ i: Int) -> Double { origin + Double(i) * cell }
  static func y(_ j: Int) -> Double { origin + Double(j) * cell }

  /// Nearest grid index, clamped to the grid.
  static func index(_ x: Double, _ y: Double) -> Int {
    let i = Int(((x - origin) / cell).rounded(.toNearestOrEven))
    let j = Int(((y - origin) / cell).rounded(.toNearestOrEven))
    return min(max(j, 0), ny - 1) * nx + min(max(i, 0), nx - 1)
  }

  static func dist(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(b.x - a.x, b.y - a.y) }

  static func length(_ p: [CGPoint]) -> Double {
    zip(p, p.dropFirst()).reduce(0) { $0 + dist($1.0, $1.1) }
  }

  // MARK: Marching squares

  private static let nodeKinds = 3

  private static func node(_ kind: Int, _ i: Int, _ j: Int) -> Int { (kind * ny + j) * nx + i }

  /// Contours of `field` at `level`, as (points, closed) in map units.
  static func march(_ field: [Double], level: Double) -> [(points: [CGPoint], closed: Bool)] {
    var segs: [(Int, Int)] = []
    for j in 0..<(ny - 1) {
      for i in 0..<(nx - 1) {
        let v00 = field[j * nx + i]
        let v10 = field[j * nx + i + 1]
        let v11 = field[(j + 1) * nx + i + 1]
        let v01 = field[(j + 1) * nx + i]
        let a = v00 > level
        let b = v10 > level
        let c = v11 > level
        let d = v01 > level
        if a == b && b == c && c == d { continue }
        let top = node(0, i, j)
        let right = node(1, i + 1, j)
        let bot = node(0, i, j + 1)
        let left = node(1, i, j)
        var act: [Int] = []
        if a != b { act.append(top) }
        if b != c { act.append(right) }
        if d != c { act.append(bot) }
        if a != d { act.append(left) }
        if act.count == 2 {
          segs.append((act[0], act[1]))
        } else {
          let hi = (v00 + v10 + v01 + v11) / 4 > level
          if a && c {
            segs += hi ? [(top, right), (bot, left)] : [(top, left), (right, bot)]
          } else {
            segs += hi ? [(top, left), (right, bot)] : [(top, right), (bot, left)]
          }
        }
      }
    }
    return chain(segs).map { line in
      let points = line.map { key -> CGPoint in
        let i = key % nx
        let j = (key / nx) % ny
        if key / (nx * ny) == 0 {
          let a = field[j * nx + i]
          let q = (level - a) / (field[j * nx + i + 1] - a)
          return CGPoint(x: origin + (Double(i) + q) * cell, y: origin + Double(j) * cell)
        }
        let a = field[j * nx + i]
        let q = (level - a) / (field[(j + 1) * nx + i] - a)
        return CGPoint(x: origin + Double(i) * cell, y: origin + (Double(j) + q) * cell)
      }
      return (points, line.first == line.last)
    }
  }

  /// Boundaries between regions of a label grid, through edge midpoints and cell centres.
  static func borders(_ labels: [Int32], keep: (CGPoint, CGPoint) -> Bool) -> [[CGPoint]] {
    func mid(_ key: Int) -> CGPoint {
      let i = Double(key % nx)
      let j = Double((key / nx) % ny)
      switch key / (nx * ny) {
      case 0: return CGPoint(x: origin + (i + 0.5) * cell, y: origin + j * cell)
      case 1: return CGPoint(x: origin + i * cell, y: origin + (j + 0.5) * cell)
      default: return CGPoint(x: origin + (i + 0.5) * cell, y: origin + (j + 0.5) * cell)
      }
    }
    var segs: [(Int, Int)] = []
    for j in 0..<(ny - 1) {
      for i in 0..<(nx - 1) {
        let l00 = labels[j * nx + i]
        let l10 = labels[j * nx + i + 1]
        let l11 = labels[(j + 1) * nx + i + 1]
        let l01 = labels[(j + 1) * nx + i]
        if l00 == l10 && l10 == l11 && l11 == l01 { continue }
        var act: [Int] = []
        if l00 != l10 { act.append(node(0, i, j)) }
        if l10 != l11 { act.append(node(1, i + 1, j)) }
        if l01 != l11 { act.append(node(0, i, j + 1)) }
        if l00 != l01 { act.append(node(1, i, j)) }
        if act.count == 2 {
          segs.append((act[0], act[1]))
        } else {
          let centre = node(2, i, j)
          segs += act.map { ($0, centre) }
        }
      }
    }
    let kept = segs.filter { keep(mid($0.0), mid($0.1)) }
    return chain(kept).compactMap { line in
      let points = line.map(mid)
      guard length(points) > 6 else { return nil }
      let closed = line.first == line.last
      return simplify(chaikin(points, closed: closed), closed: closed, eps: 0.3)
    }
  }

  /// Joins segments into polylines: open chains from their ends first, then loops.
  private static func chain(_ segs: [(Int, Int)]) -> [[Int]] {
    let nodes = nodeKinds * nx * ny
    var degree = [Int](repeating: 0, count: nodes)
    var adjacent = [Int](repeating: 0, count: nodes * 4)
    var order: [Int] = []
    for (k, (u, v)) in segs.enumerated() {
      for n in [u, v] {
        if degree[n] == 0 { order.append(n) }
        adjacent[n * 4 + degree[n]] = k
        degree[n] += 1
      }
    }
    var used = [Bool](repeating: false, count: segs.count)
    func walk(_ start: Int, _ first: Int) -> [Int] {
      var node = start
      var k = first
      var line = [node]
      while true {
        used[k] = true
        node = segs[k].0 == node ? segs[k].1 : segs[k].0
        line.append(node)
        if degree[node] != 2 { break }
        guard let next = (0..<2).map({ adjacent[node * 4 + $0] }).first(where: { !used[$0] }) else { break }
        k = next
      }
      return line
    }
    var out: [[Int]] = []
    for n in order where degree[n] != 2 {
      for s in 0..<degree[n] where !used[adjacent[n * 4 + s]] {
        out.append(walk(n, adjacent[n * 4 + s]))
      }
    }
    for k in segs.indices where !used[k] {
      out.append(walk(segs[k].0, k))
    }
    return out
  }

  // MARK: Line work

  static func chaikin(_ input: [CGPoint], closed: Bool, iterations: Int = 2) -> [CGPoint] {
    var p = input
    for _ in 0..<iterations {
      if closed {
        let q = p.first == p.last ? Array(p.dropLast()) : p
        guard q.count > 1 else { return p }
        var r: [CGPoint] = []
        r.reserveCapacity(q.count * 2 + 1)
        for k in q.indices {
          let a = q[k]
          let b = q[(k + 1) % q.count]
          r.append(CGPoint(x: a.x * 0.75 + b.x * 0.25, y: a.y * 0.75 + b.y * 0.25))
          r.append(CGPoint(x: a.x * 0.25 + b.x * 0.75, y: a.y * 0.25 + b.y * 0.75))
        }
        p = r + [r[0]]
      } else {
        guard p.count > 1 else { return p }
        var r = [p[0]]
        r.reserveCapacity(p.count * 2)
        for (a, b) in zip(p, p.dropFirst()) {
          r.append(CGPoint(x: a.x * 0.75 + b.x * 0.25, y: a.y * 0.75 + b.y * 0.25))
          r.append(CGPoint(x: a.x * 0.25 + b.x * 0.75, y: a.y * 0.25 + b.y * 0.75))
        }
        r.append(p[p.count - 1])
        p = r
      }
    }
    return p
  }

  /// Ramer-Douglas-Peucker.
  static func rdp(_ p: [CGPoint], eps: Double) -> [CGPoint] {
    guard p.count >= 3 else { return p }
    var out: [CGPoint] = []
    func emit(_ lo: Int, _ hi: Int) {
      guard hi - lo >= 2 else {
        out.append(p[lo])
        return
      }
      let dx = p[hi].x - p[lo].x
      let dy = p[hi].y - p[lo].y
      var l = hypot(dx, dy)
      if l == 0 { l = 1e-9 }
      var best = -1.0
      var bi = lo
      for k in (lo + 1)..<hi {
        let dd = abs(dy * (p[k].x - p[lo].x) - dx * (p[k].y - p[lo].y)) / l
        if dd > best {
          best = dd
          bi = k
        }
      }
      if best > eps {
        emit(lo, bi)
        emit(bi, hi)
      } else {
        out.append(p[lo])
      }
    }
    emit(0, p.count - 1)
    out.append(p[p.count - 1])
    return out
  }

  static func simplify(_ p: [CGPoint], closed: Bool, eps: Double) -> [CGPoint] {
    guard closed else { return rdp(p, eps: eps) }
    let q = Array(p.dropLast())
    guard q.count > 2 else { return p }
    let m = q.count / 2
    let a = rdp(Array(q[0...m]), eps: eps)
    let b = rdp(Array(q[m...]) + [q[0]], eps: eps)
    return Array(a.dropLast()) + b
  }

  /// Distance (in cells) to the nearest `true` cell; two-pass chamfer.
  static func chamfer(_ mask: [Bool]) -> [Double] {
    let r2 = 1.4142
    var d = mask.map { $0 ? 0.0 : 1e9 }
    for j in 0..<ny {
      for i in 0..<nx {
        var v = d[j * nx + i]
        if v == 0 { continue }
        if i > 0 { v = min(v, d[j * nx + i - 1] + 1) }
        if j > 0 {
          v = min(v, d[(j - 1) * nx + i] + 1)
          if i > 0 { v = min(v, d[(j - 1) * nx + i - 1] + r2) }
          if i < nx - 1 { v = min(v, d[(j - 1) * nx + i + 1] + r2) }
        }
        d[j * nx + i] = v
      }
    }
    for j in stride(from: ny - 1, through: 0, by: -1) {
      for i in stride(from: nx - 1, through: 0, by: -1) {
        var v = d[j * nx + i]
        if v == 0 { continue }
        if i < nx - 1 { v = min(v, d[j * nx + i + 1] + 1) }
        if j < ny - 1 {
          v = min(v, d[(j + 1) * nx + i] + 1)
          if i < nx - 1 { v = min(v, d[(j + 1) * nx + i + 1] + r2) }
          if i > 0 { v = min(v, d[(j + 1) * nx + i - 1] + r2) }
        }
        d[j * nx + i] = v
      }
    }
    return d
  }

  static func blur(_ field: [Double], passes: Int) -> [Double] {
    var f = field
    for _ in 0..<passes {
      var g = f
      for j in 1..<(ny - 1) {
        for i in 1..<(nx - 1) {
          let k = j * nx + i
          g[k] = (f[k] * 4 + f[k - 1] + f[k + 1] + f[k - nx] + f[k + nx]) / 8
        }
      }
      f = g
    }
    return f
  }

  static func catmull(_ pts: [CGPoint], per: Int = 14) -> [CGPoint] {
    let p = [pts[0]] + pts + [pts[pts.count - 1]]
    var out: [CGPoint] = []
    for k in stride(from: 1, to: p.count - 2, by: 1) {
      let p0 = p[k - 1]
      let p1 = p[k]
      let p2 = p[k + 1]
      let p3 = p[k + 2]
      for s in 0..<per {
        let t = Double(s) / Double(per)
        let t2 = t * t
        let t3 = t2 * t
        func axis(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
          0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
        }
        out.append(CGPoint(x: axis(p0.x, p1.x, p2.x, p3.x), y: axis(p0.y, p1.y, p2.y, p3.y)))
      }
    }
    out.append(pts[pts.count - 1])
    return out
  }

  static func resample(_ p: [CGPoint], step: Double) -> [CGPoint] {
    var out = [p[0]]
    var acc = 0.0
    for (start, b) in zip(p, p.dropFirst()) {
      var a = start
      var seg = dist(a, b)
      while acc + seg >= step {
        let t = (step - acc) / seg
        a = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        out.append(a)
        seg = dist(a, b)
        acc = 0
      }
      acc += seg
    }
    out.append(p[p.count - 1])
    return out
  }

  static func roman(_ number: Int) -> String {
    let table = [
      (1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"),
      (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I"),
    ]
    var n = number
    var out = ""
    for (value, symbol) in table {
      while n >= value {
        out += symbol
        n -= value
      }
    }
    return out
  }
}
