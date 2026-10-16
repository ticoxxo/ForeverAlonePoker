import SwiftUI

/// A round profile picture. Without a picture it shows the player's initials
/// when a name is given, otherwise a generic silhouette.
struct AvatarView: View {
    let data: Data?
    let size: CGFloat
    var name: String? = nil

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let name, !Self.initials(of: name).isEmpty {
                Text(Self.initials(of: name))
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.gradient)
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel(Text(name.map { "Profile picture of \($0)" } ?? "Profile picture"))
    }

    /// Up to two letters: the first letters of the first and last words.
    nonisolated static func initials(of name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        let letters = [words.first, words.count > 1 ? words.last : nil].compactMap { $0?.first }
        return String(letters).uppercased()
    }
}
