import SwiftUI

/// Native San Francisco, using semantic sizes so the approved typography scales.
enum ScoringStyle {
    static let projection = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.60, green: 0.75, blue: 1, alpha: 1)
            : UIColor(red: 0.13, green: 0.36, blue: 0.68, alpha: 1)
    })
    static let positive = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.64, green: 0.87, blue: 0.34, alpha: 1)
            : UIColor(red: 0.20, green: 0.42, blue: 0.07, alpha: 1)
    })
    static let negative = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.73, blue: 0.46, alpha: 1)
            : UIColor(red: 0.59, green: 0.31, blue: 0.02, alpha: 1)
    })
    static let heroProjection = Color(red: 0.66, green: 0.78, blue: 1)
    static let heroSecondary = Color(red: 0.72, green: 0.78, blue: 0.86)
}

struct ProjectionCaption: View {
    let text: String
    var pregame = false
    var onDark = false
    var liveEstimate = false
    var body: some View {
        Text("\(liveEstimate ? "Live est." : (pregame ? "Pregame proj." : "Proj.")) \(text)")
            .font(.caption).monospacedDigit()
            .foregroundStyle(onDark ? ScoringStyle.heroProjection : ScoringStyle.projection)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("\(liveEstimate ? "Estimated final score" : "Pregame projection"), \(text == "—" ? "unavailable" : text + " points")")
    }
}
