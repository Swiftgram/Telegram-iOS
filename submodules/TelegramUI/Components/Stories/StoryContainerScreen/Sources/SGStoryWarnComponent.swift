import SGStrings

import Foundation
import UIKit
import Display
import ComponentFlow
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import MultilineTextComponent
import BalancedTextComponent
import TelegramCore
import ButtonComponent

final class SGStoryWarningComponent: Component {
    let context: AccountContext
    let theme: PresentationTheme
    let strings: PresentationStrings
    let peer: EnginePeer?
    let isInStealthMode: Bool
    let action: () -> Void
    let close: () -> Void
    
    init(
        context: AccountContext,
        theme: PresentationTheme,
        strings: PresentationStrings,
        peer: EnginePeer? = nil,
        isInStealthMode: Bool,
        action: @escaping () -> Void,
        close: @escaping () -> Void
    ) {
        self.context = context
        self.theme = theme
        self.peer = peer
        self.strings = strings
        self.isInStealthMode = isInStealthMode
        self.action = action
        self.close = close
    }
    
    static func ==(lhs: SGStoryWarningComponent, rhs: SGStoryWarningComponent) -> Bool {
        if lhs.theme !== rhs.theme {
            return false
        }
        return true
    }
    
    final class View: UIView {
        private var component: SGStoryWarningComponent?
        private weak var state: EmptyComponentState?
        
        private let effectView: UIVisualEffectView
        private let containerView = UIView()
        private let titleLabel = ComponentView<Empty>()
        private let descriptionLabel = ComponentView<Empty>()
        private let actionButton = ComponentView<Empty>()
        
        let closeButton: HighlightableButton
        
        override init(frame: CGRect) {
            self.effectView = UIVisualEffectView(effect: nil)
            
            self.closeButton = HighlightableButton()
            
            super.init(frame: frame)
            
            self.addSubview(self.effectView)
            self.addSubview(self.containerView)
            
            self.actionButton.view?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.handleProceed)))
            // Configure closeButton
            if let image = UIImage(named: "Stories/Close") {
                closeButton.setImage(image, for: .normal)
            }
            closeButton.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
            self.addSubview(closeButton)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        @objc private func handleProceed() {
            if let component = self.component {
                component.action()
            }
        }
        
        @objc private func handleClose() {
            if let component = self.component {
                component.close()
            }
        }
        
        var didAnimateOut = false
        
        func animateIn() {
            self.didAnimateOut = false
            UIView.animate(withDuration: 0.2) {
                self.effectView.effect = UIBlurEffect(style: .dark)
            }
            self.containerView.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.3)
            self.containerView.layer.animateScale(from: 0.85, to: 1.0, duration: 0.4, timingFunction: kCAMediaTimingFunctionSpring)
        }
        
        func animateOut(completion: @escaping () -> Void) {
            guard !self.didAnimateOut else {
                return
            }
            self.didAnimateOut = true
            self.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2, removeOnCompletion: false, completion: { _ in
                completion()
            })
            self.containerView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false)
            self.containerView.layer.animateScale(from: 1.0, to: 1.1, duration: 0.4, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
        }
        
        func update(component: SGStoryWarningComponent, availableSize: CGSize, transition: ComponentTransition) -> CGSize {
            self.component = component
            
            let sideInset: CGFloat = 48.0
            let topInset: CGFloat = min(48.0, floor(availableSize.width * 0.1))
            let navigationStripTopInset: CGFloat = 15.0
            
            let closeButtonSize = CGSize(width: 50.0, height: 64.0)
            self.closeButton.frame = CGRect(origin: CGPoint(x: availableSize.width - closeButtonSize.width, y: navigationStripTopInset + topInset), size: closeButtonSize)
            
            var authorName = i18n("Stories.Warning.Author", component.strings.baseLanguageCode)
            if let peer = component.peer {
                authorName = peer.displayTitle(strings: component.strings, displayOrder: .firstLast)
            }
            
            let titleSize = self.titleLabel.update(
                transition: .immediate,
                component: AnyComponent(
                    MultilineTextComponent(
                        text: .plain(NSAttributedString(
                            string: i18n("Stories.Warning.ViewStory", component.strings.baseLanguageCode),
                            font: Font.semibold(20.0),
                            textColor: .white,
                            paragraphAlignment: .center
                        ))
                    )
                ),
                environment: {},
                containerSize: CGSize(width: availableSize.width - sideInset * 2.0, height: availableSize.height)
            )
            
            let textSize = self.descriptionLabel.update(
                transition: .immediate,
                component: AnyComponent(
                    BalancedTextComponent(
                        text: .plain(NSAttributedString(
                            string: i18n(component.isInStealthMode ? "Stories.Warning.NoticeStealth" : "Stories.Warning.Notice", component.strings.baseLanguageCode, authorName),
                            font: Font.regular(15.0),
                            textColor: UIColor(rgb: 0xffffff, alpha: 0.6),
                            paragraphAlignment: .center
                        )),
                        maximumNumberOfLines: 0,
                        lineSpacing: 0.2
                    )
                ),
                environment: {},
                containerSize: CGSize(width: availableSize.width - sideInset * 2.0, height: availableSize.height)
            )
            
            let buttonSize = self.actionButton.update(
                transition: .immediate,
                component: AnyComponent(
                    ButtonComponent(
                        background: ButtonComponent.Background(
                            color: component.theme.list.itemCheckColors.fillColor,
                            foreground: component.theme.list.itemCheckColors.foregroundColor,
                            pressedColor: component.theme.list.itemCheckColors.fillColor.withMultipliedAlpha(0.9)
                        ),
                        content: AnyComponentWithIdentity(
                            id: component.strings.Chat_StoryMentionAction,
                            component: AnyComponent(ButtonTextContentComponent(
                                text: component.strings.Chat_StoryMentionAction,
                                badge: 0,
                                textColor: component.theme.list.itemCheckColors.foregroundColor,
                                badgeBackground: component.theme.list.itemCheckColors.foregroundColor,
                                badgeForeground: component.theme.list.itemCheckColors.fillColor
                            ))
                        ),
                        isEnabled: true,
                        displaysProgress: false,
                        action: { [weak self] in
                            self?.handleProceed()
                        }
                    )
                )
                ,
                environment: {},
                containerSize: CGSize(width: availableSize.width - sideInset * 2.0, height: 50.0)
            )
            
            
            let totalHeight = titleSize.height + 7.0 + textSize.height + 50.0 + buttonSize.height
            let originY = (availableSize.height - totalHeight) / 2.0
            
            let titleFrame = CGRect(
                origin: CGPoint(x: (availableSize.width - titleSize.width) / 2.0, y: originY),
                size: titleSize
            )
            if let view = self.titleLabel.view {
                if view.superview == nil {
                    self.containerView.addSubview(view)
                }
                view.frame = titleFrame
            }
            
            let textFrame = CGRect(
                origin: CGPoint(x: (availableSize.width - textSize.width) / 2.0, y: titleFrame.maxY + 7.0),
                size: textSize
            )
            if let view = self.descriptionLabel.view {
                if view.superview == nil {
                    self.containerView.addSubview(view)
                }
                view.frame = textFrame
            }
            
            let buttonFrame = CGRect(
                origin: CGPoint(x: (availableSize.width - buttonSize.width) / 2.0, y: textFrame.maxY + 50.0),
                size: buttonSize
            )
            if let view = self.actionButton.view {
                if view.superview == nil {
                    self.containerView.addSubview(view)
                }
                view.frame = buttonFrame
            }
            
            let bounds = CGRect(origin: .zero, size: availableSize)
            self.effectView.frame = bounds
            self.containerView.frame = bounds
            
            return availableSize
        }
        
    }
    
    func makeView() -> View {
        return View(frame: CGRect())
    }
    
    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, transition: transition)
    }
}
