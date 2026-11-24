import Foundation
import SwiftUI

// Synthetic demo content for design review. None of these books, ratings or people are real.

struct DemoMember: Identifiable, Hashable {
  let id: String
  let name: String
  let color: Color
  var isAdmin = false
  var note: String?

  var initial: String { String(name.prefix(1)) }
}

enum DemoRequestStatus: Hashable {
  case searching
  case downloading(Double)
  case awaitingRelease(String)
  case available

  var label: String {
    switch self {
    case .searching: "Searching"
    case .downloading(let p): "Downloading \(Int(p * 100))%"
    case .awaitingRelease(let date): "Awaiting release · \(date)"
    case .available: "Ready"
    }
  }
}

struct DemoBook: Identifiable, Hashable {
  let id: String
  let title: String
  let author: String
  var narrator = ""
  var series: String?
  var seriesIndex: Int?
  var hours: Double = 10
  /// 0...1 of the whole book heard.
  var progress: Double = 0
  var chapterCount = 30
  var currentChapter = 1
  var chapterTitle = ""
  var chapterProgress: Double = 0
  var chapterRemaining = ""
  var timeLeft = ""
  var rating: Double = 4.5
  var ratingCount = 1000
  var genre = "Fiction"
  var cover: CoverSpec
  var request: DemoRequestStatus?
  var releaseDate: String?
  var finishedOn: String?
  var inLibrary = true

  var isFinished: Bool { progress >= 1 }
  var isStarted: Bool { progress > 0 }

  /// Start of each chapter as a fraction of the book, for the reveal's tick marks.
  var chapterStarts: [Double] {
    guard chapterCount > 1 else { return [0] }
    if id == Demo.saltRoad.id {
      // Long opening chapters, shorter ones later: chapter 14 starts at 0.55.
      let early = (0..<13).map { Double($0) * 0.55 / 13 }
      let late = (0..<(chapterCount - 13)).map { 0.55 + Double($0) * 0.45 / Double(chapterCount - 13) }
      return early + late
    }
    return (0..<chapterCount).map { Double($0) / Double(chapterCount) }
  }
}

enum Demo {
  static let jason = DemoMember(id: "u_jason", name: "Jason", color: Color(sirenHex: 0x3B4A5C), isAdmin: true)
  static let sarah = DemoMember(id: "u_sarah", name: "Sarah", color: Color(sirenHex: 0x8E4A8C))
  static let kids = DemoMember(
    id: "u_kids", name: "Kids", color: Color(sirenHex: 0x2F7D4F), note: "Kids library only")
  static let household = [sarah, kids]

  static let saltRoad = DemoBook(
    id: "li_salt_road_2", title: "The Salt Road", author: "Mara Kessling", narrator: "Daniel Okafor",
    series: "Tidewater Saga", seriesIndex: 2, hours: 14.5, progress: 0.57, chapterCount: 38,
    currentChapter: 14, chapterTitle: "The Lantern Keeper", chapterProgress: 0.40,
    chapterRemaining: "18:42", timeLeft: "6h 12m", rating: 4.7, ratingCount: 12_408,
    genre: "Fantasy", cover: .saltRoad)

  static let harborOfBells = DemoBook(
    id: "li_harbor_of_bells_1", title: "Harbor of Bells", author: "Mara Kessling",
    narrator: "Daniel Okafor", series: "Tidewater Saga", seriesIndex: 1, hours: 12.2, progress: 1,
    chapterCount: 34, rating: 4.6, ratingCount: 18_920, genre: "Fantasy",
    cover: CoverSpec(layout: .tower, palette: .slateSea, title: "Harbor of Bells", author: "Mara Kessling"),
    finishedOn: "Oct 2")

  static let ninthTide = DemoBook(
    id: "li_ninth_tide_3", title: "The Ninth Tide", author: "Mara Kessling", narrator: "Daniel Okafor",
    series: "Tidewater Saga", seriesIndex: 3, hours: 15.8, chapterCount: 41, rating: 4.8,
    ratingCount: 6_204, genre: "Fantasy",
    cover: CoverSpec(layout: .ship, palette: .midnight, title: "The Ninth Tide", author: "Mara Kessling"),
    request: .downloading(0.62), inLibrary: false)

  static let stormglass = DemoBook(
    id: "asin_stormglass_4", title: "Stormglass", author: "Mara Kessling", narrator: "Daniel Okafor",
    series: "Tidewater Saga", seriesIndex: 4, hours: 0, chapterCount: 1, rating: 0, ratingCount: 0,
    genre: "Fantasy",
    cover: CoverSpec(layout: .waves, palette: .slateSea, title: "Stormglass", author: "Mara Kessling"),
    releaseDate: "Jun 9, 2027", inLibrary: false)

  static let glassOrchard = DemoBook(
    id: "li_glass_orchard", title: "The Glass Orchard", author: "Ines Calloway", narrator: "Priya Nand",
    hours: 11.1, progress: 0.41, chapterCount: 26, currentChapter: 11, chapterTitle: "Grafting",
    chapterProgress: 0.7, chapterRemaining: "07:15", timeLeft: "6h 33m", rating: 4.5,
    ratingCount: 9_870, genre: "Literary",
    cover: CoverSpec(layout: .tree, palette: .orchard, title: "The Glass Orchard", author: "Ines Calloway"))

  static let emberAndAsh = DemoBook(
    id: "li_ember_and_ash", title: "Ember & Ash", author: "T. R. Halvorsen", narrator: "Lena Morrow",
    hours: 13.4, chapterCount: 32, rating: 4.3, ratingCount: 3_118, genre: "Mystery",
    cover: CoverSpec(layout: .mountains, palette: .ember, title: "Ember & Ash", author: "T. R. Halvorsen"),
    request: .searching, inLibrary: false)

  static let lanternCountry = DemoBook(
    id: "li_lantern_country", title: "Lantern Country", author: "Ruth Abernathy",
    narrator: "Celia Hart", hours: 9.6, chapterCount: 24, rating: 0, ratingCount: 0, genre: "Fiction",
    cover: CoverSpec(layout: .moonHills, palette: .dusk, title: "Lantern Country", author: "Ruth Abernathy"),
    request: .awaitingRelease("Mar 3"), releaseDate: "Mar 3, 2027", inLibrary: false)

  static let wolves = DemoBook(
    id: "li_wolves_quiet_shore", title: "Wolves of the Quiet Shore", author: "Callum Reyes",
    narrator: "Tom Ashby", hours: 16.2, chapterCount: 44, rating: 4.8, ratingCount: 8_113,
    genre: "Fantasy",
    cover: CoverSpec(layout: .mountains, palette: .dusk, title: "Wolves of the Quiet Shore", author: "Callum Reyes"),
    inLibrary: false)

  static let smallHours = DemoBook(
    id: "li_map_small_hours", title: "A Map of Small Hours", author: "Noor Haddad",
    narrator: "Amira Saleh", hours: 8.7, progress: 1, chapterCount: 22, rating: 4.4,
    ratingCount: 5_402, genre: "Literary",
    cover: CoverSpec(layout: .moonHills, palette: .rose, title: "A Map of Small Hours", author: "Noor Haddad"),
    finishedOn: "Sep 14")

  static let cartographersWidow = DemoBook(
    id: "li_cartographers_widow", title: "The Cartographer's Widow", author: "Elena Marsh",
    narrator: "Fiona Grey", hours: 12.9, progress: 0.12, chapterCount: 30, rating: 4.2,
    ratingCount: 2_771, genre: "Mystery",
    cover: CoverSpec(layout: .tower, palette: .forest, title: "The Cartographer's Widow", author: "Elena Marsh"))

  static let ironAndOrchid = DemoBook(
    id: "li_iron_and_orchid", title: "Iron and Orchid", author: "Sam Whitlock", narrator: "Jon Reyes",
    hours: 10.4, chapterCount: 28, rating: 4.1, ratingCount: 1_960, genre: "Science Fiction",
    cover: CoverSpec(layout: .tree, palette: .rose, title: "Iron and Orchid", author: "Sam Whitlock"))

  static let tidewater = [harborOfBells, saltRoad, ninthTide, stormglass]
  static let requests = [ninthTide, emberAndAsh, lanternCountry]

  static let library: [DemoBook] = [
    saltRoad, glassOrchard, cartographersWidow, harborOfBells, smallHours, ironAndOrchid,
  ] + finished2026.dropFirst(2).prefix(9)

  /// The 14 books finished this year (personal goal: 20).
  static let finished2026: [DemoBook] = {
    let titles: [(String, String, CoverLayout, CoverPalette)] = [
      ("Harbor of Bells", "Mara Kessling", .tower, .slateSea),
      ("A Map of Small Hours", "Noor Haddad", .moonHills, .rose),
      ("The Long Quiet", "Ada Brennan", .moonHills, .midnight),
      ("North of Everything", "Kit Lawson", .mountains, .slateSea),
      ("The Beekeeper's Year", "June Abara", .tree, .orchard),
      ("Copper Sky", "Wes Talbot", .sunSea, .ember),
      ("The House on Wren Lane", "Mae Collier", .tower, .rose),
      ("Small Gods of Winter", "Ivo Petrak", .mountains, .midnight),
      ("A Field Guide to Leaving", "Rosa Lind", .tree, .forest),
      ("The Ferryman's Daughter", "Hal Mercer", .ship, .slateSea),
      ("Orchard Weather", "Lise Moreau", .sunSea, .orchard),
      ("Glass Harbor", "Theo Vance", .waves, .midnight),
      ("The Ninth Floor", "Dana Ruiz", .tower, .dusk),
      ("Saltwater Psalms", "Odette Gray", .waves, .forest),
    ]
    return titles.enumerated().map { i, t in
      DemoBook(
        id: "li_done_\(i)", title: t.0, author: t.1, progress: 1,
        cover: CoverSpec(layout: t.2, palette: t.3, title: t.0, author: t.1))
    }
  }()

  static let yearlyGoal = 20

  /// What Jason sent Sarah, shown on her Home as "From Jason".
  static let sentToSarah: [(book: DemoBook, sent: String, note: String?, progress: Double)] = [
    (harborOfBells, "today", "Start with the first one. You'll love the ferry chapter.", 0),
    (saltRoad, "today", nil, 0),
    (glassOrchard, "Nov 18", nil, 0.41),
  ]
  static let catalogResults: [DemoBook] = [ninthTide, stormglass, saltRoad, harborOfBells, wolves]
}
