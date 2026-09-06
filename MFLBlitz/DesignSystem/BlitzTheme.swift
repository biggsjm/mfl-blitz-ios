import SwiftUI

extension Color {
    static let blitzNavy = Color(red: 0.025, green: 0.055, blue: 0.13)
    static let blitzGreen = Color(red: 0.50, green: 0.84, blue: 0.05)
    static let blitzOrange = Color(red: 0.98, green: 0.45, blue: 0.16)
    static let blitzCream = Color(red: 0.97, green: 0.96, blue: 0.91)
    static let blitzSky = Color(red: 0.30, green: 0.67, blue: 0.98)
}

enum BlitzMetrics {
    static let cornerRadius: CGFloat = 20
    static let compactCornerRadius: CGFloat = 13
    static let pagePadding: CGFloat = 16
    static let maxReadableWidth: CGFloat = 760
    static let minimumTapTarget: CGFloat = 44
}

struct PageBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
    }
}

extension View {
    func pageBackground() -> some View { modifier(PageBackground()) }

    func readablePageWidth() -> some View {
        frame(maxWidth: BlitzMetrics.maxReadableWidth, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct SurfaceCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: BlitzMetrics.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BlitzMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(.primary.opacity(0.06))
            }
    }
}

struct TeamMark: View {
    let abbreviation: String
    let seed: Int
    var size: CGFloat = 44

    private var color: Color {
        let colors: [Color] = [.blitzSky, .purple, .orange, .teal, .indigo, .pink, .mint]
        return colors[abs(seed) % colors.count]
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
                .fill(color.gradient)
            Text(abbreviation.prefix(3).uppercased())
                .font(.system(size: size * 0.28, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .padding(4)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct StatusPill: View {
    enum Tone {
        case neutral
        case live
        case positive
        case warning

        var foreground: Color {
            switch self {
            case .neutral: .secondary
            case .live: .red
            case .positive: .green
            case .warning: .orange
            }
        }
    }

    let text: String
    let systemImage: String?
    var tone: Tone = .neutral

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if let systemImage {
                Image(systemName: systemImage)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, 9)
        .frame(minHeight: 28)
        .background(tone.foreground.opacity(0.11), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct EmptyState: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
    }
}

struct DemoBanner: View {
    var body: some View {
        Label("Preview mode · Changes stay on this device", systemImage: "sparkles")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.blitzNavy)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(Color.blitzGreen.opacity(0.92))
            .accessibilityLabel("Preview mode. Changes stay on this device.")
    }
}

struct LiveWriteSafetyBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "lock.shield.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(Color.orange.opacity(0.12))
            .accessibilityLabel(message.replacingOccurrences(of: "·", with: "."))
    }
}

struct WeekPicker: View {
    @Binding var selection: Int
    let range: ClosedRange<Int>

    var body: some View {
        Menu {
            Picker("Week", selection: $selection) {
                ForEach(range, id: \.self) { week in
                    Text("Week \(week)").tag(week)
                }
            }
        } label: {
            Label("Week \(selection)", systemImage: "calendar")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: BlitzMetrics.minimumTapTarget)
        }
        .accessibilityHint("Choose another scoring week")
    }
}

struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    var isBusy = false
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .tint(.blitzNavy)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.headline)
            .foregroundStyle(Color.blitzNavy)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.blitzGreen, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isBusy)
        .opacity(isDisabled ? 0.45 : 1)
    }
}
