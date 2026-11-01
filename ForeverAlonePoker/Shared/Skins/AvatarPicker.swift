import SwiftUI
import SkinKit

/// Picks the player's profile picture from the ones they can use: the free
/// pictures and any they bought (tdr/0030). "None" goes back to initials.
/// Lives in Shared so the Profile feature can show it without the store.
struct AvatarPicker: View {
    @Environment(SkinStore.self) private var skins
    @ScaledMetric(relativeTo: .body) private var tileSize: CGFloat = 56

    private var usable: [SkinItem] {
        skins.items(of: .avatar).filter { skins.owns(.avatar, of: $0) }
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: min(tileSize, 88) + Theme.Spacing.small))], spacing: Theme.Spacing.medium) {
            tile(selected: skins.myAvatarID == nil, label: Text("No picture")) {
                skins.clearAvatar()
            } content: {
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            ForEach(usable) { item in
                tile(selected: skins.myAvatarID == item.id.rawValue, label: Text(item.name(for: Locale.current.language.languageCode?.identifier))) {
                    skins.equip(item, on: [.avatar])
                } content: {
                    AvatarView(avatarID: item.id.rawValue, size: min(tileSize, 88))
                }
            }
        }
        .padding(.vertical, Theme.Spacing.small)
    }

    private func tile(
        selected: Bool,
        label: Text,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> some View
    ) -> some View {
        Button(action: action) {
            content()
                .frame(width: min(tileSize, 88), height: min(tileSize, 88))
                .overlay {
                    Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3)
                }
                .padding(2)
        }
        .buttonStyle(.plain)
        .frame(minWidth: Theme.Target.minimum, minHeight: Theme.Target.minimum)
        .accessibilityLabel(label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
