import PlayerIntents
import SwiftUI

extension Color {
  static var widgetAccent: Color {
    // SIREN: Siren identifiers
    guard let raw = UserDefaults(suiteName: "group.com.inceptyon.siren")?.string(forKey: "accentColor"),
      let color = Color(rawValue: raw)
    else {
      return .accentColor
    }
    return color
  }
}
