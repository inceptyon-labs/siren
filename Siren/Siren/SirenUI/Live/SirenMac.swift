import UIKit

/// Mac (Catalyst) adjustments, run once the first window is up.
enum SirenMac {
  @MainActor static func configure() {
    #if targetEnvironment(macCatalyst)
    // Mac-style sliders take the system accent; the iPad style takes Siren's sea teal.
    UISlider.appearance().preferredBehavioralStyle = .pad
    // Narrower than this, Home's two columns and the player's art crowd each other.
    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
      scene.sizeRestrictions?.minimumSize = CGSize(width: 720, height: 600)
    }
    #endif
  }
}
