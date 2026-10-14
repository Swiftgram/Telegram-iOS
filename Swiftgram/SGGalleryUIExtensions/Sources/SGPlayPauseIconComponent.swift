import UIKit
import ComponentFlow
import LottieSettings
import ManagedAnimationNode

private enum SGPlayPauseIconState: Equatable {
    case play
    case pause
}

private final class SGPlayPauseIconNode: ManagedAnimationNode {
    private let duration: Double = 0.35
    private var iconState: SGPlayPauseIconState = .pause

    override init(size: CGSize, lottieSettings: LottieRenderingSettings) {
        super.init(size: size, lottieSettings: lottieSettings)

        self.trackTo(item: ManagedAnimationItem(source: .local("anim_playpause"), frames: .range(startFrame: 41, endFrame: 41), duration: 0.01))
    }

    func enqueueState(_ state: SGPlayPauseIconState, animated: Bool) {
        guard self.iconState != state else {
            return
        }

        let previousState = self.iconState
        self.iconState = state

        switch previousState {
        case .pause:
            switch state {
            case .play:
                if animated {
                    self.trackTo(item: ManagedAnimationItem(source: .local("anim_playpause"), frames: .range(startFrame: 41, endFrame: 83), duration: self.duration))
                } else {
                    self.trackTo(item: ManagedAnimationItem(source: .local("anim_playpause"), frames: .range(startFrame: 0, endFrame: 0), duration: 0.01))
                }
            case .pause:
                break
            }
        case .play:
            switch state {
            case .pause:
                if animated {
                    self.trackTo(item: ManagedAnimationItem(source: .local("anim_playpause"), frames: .range(startFrame: 0, endFrame: 41), duration: self.duration))
                } else {
                    self.trackTo(item: ManagedAnimationItem(source: .local("anim_playpause"), frames: .range(startFrame: 41, endFrame: 41), duration: 0.01))
                }
            case .play:
                break
            }
        }
    }
}

// Morphing play/pause control for the gallery footer. Mirrors the animation used by the
// on-screen `VideoPlaybackControlsComponent` / the footer's own `PlayPauseIconNode` so toggling
// playback morphs instead of cross-dissolving between two static images.
final class SGPlayPauseIconComponent: Component {
    let isPlaying: Bool
    let size: CGSize
    let lottieSettings: LottieRenderingSettings

    init(isPlaying: Bool, size: CGSize = CGSize(width: 40.0, height: 40.0), lottieSettings: LottieRenderingSettings = .noAccountFallback) {
        self.isPlaying = isPlaying
        self.size = size
        self.lottieSettings = lottieSettings
    }

    static func ==(lhs: SGPlayPauseIconComponent, rhs: SGPlayPauseIconComponent) -> Bool {
        if lhs.isPlaying != rhs.isPlaying {
            return false
        }
        if lhs.size != rhs.size {
            return false
        }
        if lhs.lottieSettings != rhs.lottieSettings {
            return false
        }
        return true
    }

    final class View: UIView {
        private var iconNode: SGPlayPauseIconNode?

        func update(component: SGPlayPauseIconComponent, availableSize: CGSize, transition: ComponentTransition) -> CGSize {
            let iconNode: SGPlayPauseIconNode
            if let current = self.iconNode, current.intrinsicSize == component.size {
                iconNode = current
            } else {
                self.iconNode?.view.removeFromSuperview()
                iconNode = SGPlayPauseIconNode(size: component.size, lottieSettings: component.lottieSettings)
                self.iconNode = iconNode
                self.addSubview(iconNode.view)
                iconNode.enqueueState(component.isPlaying ? .pause : .play, animated: false)
            }

            // The play glyph is optically off-centre inside the animation bounds; nudge it as the shared control does.
            let horizontalOffset: CGFloat = component.isPlaying ? 0.0 : 2.0
            iconNode.view.frame = CGRect(origin: CGPoint(x: horizontalOffset, y: 0.0), size: component.size)
            iconNode.enqueueState(component.isPlaying ? .pause : .play, animated: true)

            return component.size
        }
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, transition: transition)
    }
}
