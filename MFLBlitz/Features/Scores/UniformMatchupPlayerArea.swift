import SwiftUI

private struct MatchupPlayerHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MatchupPlayerAreaHeight: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

private extension EnvironmentValues {
    var matchupPlayerAreaHeight: CGFloat? {
        get { self[MatchupPlayerAreaHeight.self] }
        set { self[MatchupPlayerAreaHeight.self] = newValue }
    }
}

/// Every player gets the largest intrinsic player height in this presentation.
/// Measure before applying the shared height so shorter content can shrink the
/// whole grid again, and Dynamic Type never clips stats to a fixed point size.
struct UniformMatchupPlayerAreas: ViewModifier {
    @State private var height: CGFloat?
    func body(content: Content) -> some View {
        content.environment(\.matchupPlayerAreaHeight, height)
            .onPreferenceChange(MatchupPlayerHeightKey.self) { value in
                height = value > 0 && value.isFinite ? ceil(value) : nil
            }
    }
}

struct UniformMatchupPlayerArea: ViewModifier {
    @Environment(\.matchupPlayerAreaHeight) private var height
    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: MatchupPlayerHeightKey.self, value: geometry.size.height)
                }
            }
            .frame(height: height, alignment: .top)
    }
}
