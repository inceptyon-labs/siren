import PlayerIntents
import SwiftUI

extension Color {
  static var widgetAccent: Color {
    guard let raw = UserDefaults(suiteName: "group.com.inceptyon.siren")?.string(forKey: "accentColor"), // SIREN: Siren identifiers
      let color = Color(rawValue: raw)
    else {
      return .accentColor
    }
    return color
  }
}
