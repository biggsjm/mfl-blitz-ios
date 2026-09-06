import SwiftUI
import UIKit

/// Pre-render once per identity/artwork change; the system still owns tab layout,
/// selection, hit testing and accessibility. No raised/custom tab-bar control.
@MainActor
enum TeamTabArtwork {
    static let size = CGSize(width: 26, height: 26)

    static func image(abbreviation: String, artwork: CGImage? = nil) -> UIImage {
        let bounds = CGRect(origin: .zero, size: size)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIBezierPath(roundedRect: bounds, cornerRadius: 7).addClip()
            if let artwork {
                let source = UIImage(cgImage: artwork)
                let scale = max(size.width / source.size.width, size.height / source.size.height)
                let fitted = CGSize(width: source.size.width * scale, height: source.size.height * scale)
                source.draw(in: CGRect(x: (size.width - fitted.width) / 2,
                                       y: (size.height - fitted.height) / 2,
                                       width: fitted.width, height: fitted.height))
            } else {
                UIColor(Color.blitzGreen).setFill()
                UIBezierPath(rect: bounds).fill()
                let initials = String(abbreviation.trimmingCharacters(in: .whitespacesAndNewlines).prefix(3)).uppercased()
                let text = (initials.isEmpty ? "MY" : initials) as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: initials.count > 2 ? 9 : 11, weight: .heavy),
                    .foregroundColor: UIColor(Color.blitzNavy)
                ]
                let measured = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: (size.width - measured.width) / 2,
                                      y: (size.height - measured.height) / 2), withAttributes: attributes)
            }
        }.withRenderingMode(.alwaysOriginal)
    }
}
