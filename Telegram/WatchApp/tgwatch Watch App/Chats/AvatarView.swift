import SwiftUI
import UIKit

/// A 36pt circular chat avatar. Renders (priority): Saved-Messages bookmark glyph;
/// crisp downloaded photo; blurred minithumbnail placeholder; initials on a
/// per-chat color. Drives viewport-based download of the small photo via
/// `.onScrollVisibilityChange` (same as `PhotoBubbleView`) — only while the photo
/// exists and hasn't downloaded yet.
struct AvatarView: View {
    let avatar: AvatarVisual
    var onRequestDownload: (Int) -> Void = { _ in }
    var onCancelDownload: (Int) -> Void = { _ in }

    private let size: CGFloat = 36

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(Circle())
            .onScrollVisibilityChange(threshold: 0.01) { visible in
                guard let fileId = avatar.photoFileId, avatar.photoLocalPath == nil else { return }
                if visible {
                    onRequestDownload(fileId)
                } else {
                    onCancelDownload(fileId)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch avatar.kind {
        case .savedMessages:
            ZStack {
                Circle().fill(Color.accentColor)
                Image(systemName: "bookmark.fill")
                    .font(.system(size: size * 0.42))
                    .foregroundStyle(.white)
            }
        case .normal:
            if let path = avatar.photoLocalPath, let img = UIImage(contentsOfFile: path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else if let data = avatar.mini, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill().blur(radius: 1.5)
            } else {
                ZStack {
                    Circle().fill(avatarPalette[avatar.colorIndex])
                    Text(avatar.initials)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Avatar — initials") {
    AvatarView(avatar: AvatarVisual(kind: .normal, initials: "JS", colorIndex: 0, photoFileId: nil, photoLocalPath: nil, mini: nil))
        .padding()
}

#Preview("Avatar — single initial") {
    AvatarView(avatar: AvatarVisual(kind: .normal, initials: "T", colorIndex: 5, photoFileId: nil, photoLocalPath: nil, mini: nil))
        .padding()
}

#Preview("Avatar — saved messages") {
    AvatarView(avatar: AvatarVisual(kind: .savedMessages, initials: "", colorIndex: 0, photoFileId: nil, photoLocalPath: nil, mini: nil))
        .padding()
}

#Preview("Avatar — empty title") {
    AvatarView(avatar: AvatarVisual(kind: .normal, initials: "", colorIndex: 3, photoFileId: nil, photoLocalPath: nil, mini: nil))
        .padding()
}
#endif
