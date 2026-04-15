import Foundation
import UIKit
import SwiftSignalKit
import Display
import TelegramPresentationData
import ComponentFlow
import ComponentDisplayAdapters
import AccountContext
import ViewControllerComponent
import MultilineTextComponent
import ButtonComponent
import BundleIconComponent
import TelegramCore
import PresentationDataUtils
import ResizableSheetComponent
import GlassBarButtonComponent
import LottieComponent
import ListSectionComponent
import Markdown
import TelegramUIPreferences
import ListMultilineTextFieldItemComponent

final class TextStyleEditContentComponent: Component {
    typealias EnvironmentType = ViewControllerComponentContainer.Environment
    
    final class ExternalState {
        let titleInputState = ListMultilineTextFieldItemComponent.ExternalState()
        let textInputState = ListMultilineTextFieldItemComponent.ExternalState()
    }
    
    let externalState: ExternalState
    let context: AccountContext
    let initialText: TextWithEntities?

    init(
        externalState: ExternalState,
        context: AccountContext,
        initialText: TextWithEntities?
    ) {
        self.externalState = externalState
        self.context = context
        self.initialText = initialText
    }

    static func ==(lhs: TextStyleEditContentComponent, rhs: TextStyleEditContentComponent) -> Bool {
        return true
    }
    
    private enum Mode {
        case translate
        case stylize
        case fix
    }

    final class View: UIView {
        private var component: TextStyleEditContentComponent?
        private var environment: ViewControllerComponentContainer.Environment?
        private weak var state: EmptyComponentState?
        private var isUpdating: Bool = false
        
        private let iconBackground = ComponentView<Empty>()
        private let icon = ComponentView<Empty>()
        private let titleSection = ComponentView<Empty>()
        private let textSection = ComponentView<Empty>()
        
        override init(frame: CGRect) {
            super.init(frame: frame)
        }
        
        required init?(coder: NSCoder) {
            preconditionFailure()
        }

        func update(component: TextStyleEditContentComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<ViewControllerComponentContainer.Environment>, transition: ComponentTransition) -> CGSize {
            self.isUpdating = true
            defer {
                self.isUpdating = false
            }
            
            let alphaTransition: ComponentTransition = transition.animation.isImmediate ? .immediate : .easeInOut(duration: 0.2)
            
            let environment = environment[ViewControllerComponentContainer.Environment.self].value
            
            var resetTitle: String?
            var resetText: String?
            if self.component == nil {
                resetTitle = ""
                resetText = component.initialText?.text
            }
            
            self.component = component
            self.environment = environment
            self.state = state
            
            let sideInset: CGFloat = 16.0
            let sectionSpacing: CGFloat = 24.0
            let iconSpacing: CGFloat = 24.0

            var contentHeight: CGFloat = 0.0
            contentHeight += 70.0
            
            let iconBackgroundSize = CGSize(width: 100.0, height: 100.0)
            let _ = self.iconBackground.update(
                transition: transition,
                component: AnyComponent(FilledRoundedRectangleComponent(
                    color: environment.theme.list.itemBlocksBackgroundColor,
                    cornerRadius: .minEdge,
                    smoothCorners: false
                )),
                environment: {},
                containerSize: iconBackgroundSize
            )
            let iconBackgroundFrame = CGRect(origin: CGPoint(x: floor((availableSize.width - iconBackgroundSize.width) * 0.5), y: contentHeight), size: iconBackgroundSize)
            if let iconBackgroundView = self.iconBackground.view {
                if iconBackgroundView.superview == nil {
                    self.addSubview(iconBackgroundView)
                }
                transition.setFrame(view: iconBackgroundView, frame: iconBackgroundFrame)
            }
            
            let iconSize = self.icon.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: "📝", font: Font.regular(42.0), textColor: .black))
                )),
                environment: {},
                containerSize: iconBackgroundFrame.size
            )
            let iconFrame = iconSize.centered(in: iconBackgroundFrame)
            if let iconView = self.icon.view {
                if iconView.superview == nil {
                    self.addSubview(iconView)
                }
                transition.setFrame(view: iconView, frame: iconFrame)
            }
            
            contentHeight += iconBackgroundSize.height + iconSpacing
            
            //TODO:localize
            var titleSectionItems: [AnyComponentWithIdentity<Empty>] = []
            titleSectionItems.append(AnyComponentWithIdentity(id: 0, component: AnyComponent(ListMultilineTextFieldItemComponent(
                externalState: component.externalState.titleInputState,
                style: .glass,
                context: component.context,
                theme: environment.theme,
                strings: environment.strings,
                initialText: "",
                resetText: resetTitle.flatMap { resetTitle in
                    return ListMultilineTextFieldItemComponent.ResetText(value: resetTitle)
                },
                placeholder: "Title",
                autocapitalizationType: .none,
                autocorrectionType: .no,
                characterLimit: 256,
                emptyLineHandling: .notAllowed,
                updated: nil,
                textUpdateTransition: .spring(duration: 0.4),
                tag: nil
            ))))
            let titleSectionSize = self.titleSection.update(
                transition: transition,
                component: AnyComponent(ListSectionComponent(
                    theme: environment.theme,
                    style: .glass,
                    header: nil,
                    footer: nil,
                    items: titleSectionItems
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width - sideInset * 2.0, height: 10000.0)
            )
            let titleSectionFrame = CGRect(origin: CGPoint(x: sideInset, y: contentHeight), size: titleSectionSize)
            if let titleSectionView = self.titleSection.view {
                if titleSectionView.superview == nil {
                    self.addSubview(titleSectionView)
                    self.titleSection.parentState = state
                }
                transition.setFrame(view: titleSectionView, frame: titleSectionFrame)
            }
            contentHeight += titleSectionSize.height
            contentHeight += sectionSpacing
            
            //TODO:localize
            var textSectionItems: [AnyComponentWithIdentity<Empty>] = []
            textSectionItems.append(AnyComponentWithIdentity(id: 0, component: AnyComponent(ListMultilineTextFieldItemComponent(
                externalState: component.externalState.textInputState,
                style: .glass,
                context: component.context,
                theme: environment.theme,
                strings: environment.strings,
                initialText: "",
                resetText: resetText.flatMap { resetText in
                    return ListMultilineTextFieldItemComponent.ResetText(value: resetText)
                },
                placeholder: "Text",
                autocapitalizationType: .none,
                autocorrectionType: .no,
                characterLimit: 4096,
                emptyLineHandling: .allowed,
                updated: nil,
                textUpdateTransition: .spring(duration: 0.4),
                tag: nil
            ))))
            let textSectionSize = self.textSection.update(
                transition: transition,
                component: AnyComponent(ListSectionComponent(
                    theme: environment.theme,
                    style: .glass,
                    header: nil,
                    footer: nil,
                    items: textSectionItems
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width - sideInset * 2.0, height: 10000.0)
            )
            let textSectionFrame = CGRect(origin: CGPoint(x: sideInset, y: contentHeight), size: textSectionSize)
            if let textSectionView = self.textSection.view {
                if textSectionView.superview == nil {
                    self.addSubview(textSectionView)
                    self.textSection.parentState = state
                }
                transition.setFrame(view: textSectionView, frame: textSectionFrame)
            }
            contentHeight += textSectionSize.height
            
            contentHeight += 106.0
            
            let _ = alphaTransition

            return CGSize(width: availableSize.width, height: contentHeight)
        }
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<ViewControllerComponentContainer.Environment>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

private final class TextStyleEditSheetComponent: Component {
    typealias EnvironmentType = ViewControllerComponentContainer.Environment

    let context: AccountContext
    let initialText: TextWithEntities?
    let completion: (TelegramComposeAIMessageMode.CloudStyle) -> Void

    init(
        context: AccountContext,
        initialText: TextWithEntities?,
        completion: @escaping (TelegramComposeAIMessageMode.CloudStyle) -> Void
    ) {
        self.context = context
        self.initialText = initialText
        self.completion = completion
    }

    static func ==(lhs: TextStyleEditSheetComponent, rhs: TextStyleEditSheetComponent) -> Bool {
        return true
    }

    final class View: UIView {
        private let sheet = ComponentView<(ViewControllerComponentContainer.Environment, ResizableSheetComponentEnvironment)>()
        private let animateOut = ActionSlot<Action<Void>>()

        private var component: TextStyleEditSheetComponent?
        private var environment: ViewControllerComponentContainer.Environment?
        private weak var state: EmptyComponentState?
        
        private let contentState = TextStyleEditContentComponent.ExternalState()
        
        private var createDisposable: Disposable?

        override init(frame: CGRect) {
            super.init(frame: frame)
            
            self.contentState.titleInputState.updated = { [weak self] in
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }
                    self.state?.updated(transition: .spring(duration: 0.4))
                }
            }
            self.contentState.textInputState.updated = self.contentState.titleInputState.updated
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        deinit {
            self.createDisposable?.dispose()
        }
        
        private func performCreateStyle() {
            guard let component = self.component else {
                return
            }
            if self.contentState.titleInputState.text.string.isEmpty || self.contentState.textInputState.text.string.isEmpty {
                return
            }
            
            self.createDisposable?.dispose()
            self.createDisposable = (component.context.engine.messages.createAITextStyle(
                displayAuthor: false,
                emojiFileId: nil,
                title: self.contentState.titleInputState.text.string,
                prompt: self.contentState.textInputState.text.string
            )
            |> deliverOnMainQueue).startStrict(next: { [weak self] result in
                guard let self, let component = self.component, let environment = self.environment else {
                    return
                }
                let controller = environment.controller
                
                self.animateOut.invoke(Action { _ in
                    if let controller = controller() {
                        controller.dismiss(completion: nil)
                    }
                })
                
                component.completion(result)
            }, error: { [weak self] error in
                guard let self else {
                    return
                }
                let _ = self
            })
        }

        func update(component: TextStyleEditSheetComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<ViewControllerComponentContainer.Environment>, transition: ComponentTransition) -> CGSize {
            self.component = component
            self.state = state

            let environmentValue = environment[ViewControllerComponentContainer.Environment.self].value
            self.environment = environmentValue
            let controller = environmentValue.controller
            let theme = environmentValue.theme

            let dismiss: (Bool) -> Void = { [weak self] animated in
                if animated {
                    self?.animateOut.invoke(Action { _ in
                        if let controller = controller() {
                            controller.dismiss(completion: nil)
                        }
                    })
                } else {
                    if let controller = controller() {
                        controller.dismiss(completion: nil)
                    }
                }
            }

            let performMainAction: () -> Void = { [weak self] in
                guard let self else {
                    return
                }
                self.performCreateStyle()
            }
            let isMainActionEnabled = self.contentState.titleInputState.hasText && self.contentState.textInputState.hasText
            let actionButtonTitle: String = "Create"

            let titleString: String = "New Style"

            let sheetSize = self.sheet.update(
                transition: transition,
                component: AnyComponent(ResizableSheetComponent<ViewControllerComponentContainer.Environment>(
                    content: AnyComponent<ViewControllerComponentContainer.Environment>(TextStyleEditContentComponent(
                        externalState: self.contentState,
                        context: component.context,
                        initialText: component.initialText
                    )),
                    titleItem: AnyComponent(TitleComponent(
                        theme: theme,
                        title: titleString
                    )),
                    leftItem: AnyComponent(
                        GlassBarButtonComponent(
                            size: CGSize(width: 44.0, height: 44.0),
                            backgroundColor: nil,
                            isDark: theme.overallDarkAppearance,
                            state: .glass,
                            component: AnyComponentWithIdentity(id: "close", component: AnyComponent(
                                BundleIconComponent(
                                    name: "Navigation/Close",
                                    tintColor: theme.chat.inputPanel.panelControlColor
                                )
                            )),
                            action: { _ in
                                dismiss(true)
                            }
                        )
                    ),
                    rightItem: nil,
                    bottomItem: AnyComponent(
                        ActionButtonsComponent(
                            theme: theme,
                            strings: environmentValue.strings,
                            actionTitle: actionButtonTitle,
                            action: isMainActionEnabled ? performMainAction : nil
                        )
                    ),
                    backgroundColor: .color(theme.list.blocksBackgroundColor),
                    animateOut: self.animateOut
                )),
                environment: {
                    environmentValue
                    ResizableSheetComponentEnvironment(
                        theme: theme,
                        statusBarHeight: environmentValue.statusBarHeight,
                        safeInsets: environmentValue.safeInsets,
                        inputHeight: 0.0,
                        metrics: environmentValue.metrics,
                        deviceMetrics: environmentValue.deviceMetrics,
                        isDisplaying: environmentValue.isVisible,
                        isCentered: environmentValue.metrics.widthClass == .regular,
                        screenSize: availableSize,
                        regularMetricsSize: nil,
                        dismiss: { animated in
                            dismiss(animated)
                        }
                    )
                },
                containerSize: availableSize
            )
            self.sheet.parentState = state
            if let sheetView = self.sheet.view {
                if sheetView.superview == nil {
                    self.addSubview(sheetView)
                }
                transition.setFrame(view: sheetView, frame: CGRect(origin: .zero, size: sheetSize))
            }

            return availableSize
        }
    }

    func makeView() -> View {
        return View(frame: CGRect())
    }

    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<ViewControllerComponentContainer.Environment>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

public class TextStyleEditScreen: ViewControllerComponentContainer {
    private let context: AccountContext

    public init(
        context: AccountContext,
        theme: PresentationTheme? = nil,
        initialText: TextWithEntities?,
        completion: @escaping (TelegramComposeAIMessageMode.CloudStyle) -> Void
    ) {
        self.context = context
        
        super.init(
            context: context,
            component: TextStyleEditSheetComponent(
                context: context,
                initialText: initialText,
                completion: completion
            ),
            navigationBarAppearance: .none,
            statusBarStyle: .ignore,
            theme: theme.flatMap({ .custom($0) }) ?? .default
        )

        self.statusBar.statusBarStyle = .Ignore
        self.navigationPresentation = .flatModal
        self.blocksBackgroundWhenInOverlay = true
    }

    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
    }

    public func dismissAnimated() {
        if let view = self.node.hostView.findTaggedView(tag: ResizableSheetComponent<ViewControllerComponentContainer.Environment>.View.Tag()) as? ResizableSheetComponent<ViewControllerComponentContainer.Environment>.View {
            view.dismissAnimated()
        }
    }
}

private final class TitleComponent: Component {
    let theme: PresentationTheme
    let title: String
    
    init(
        theme: PresentationTheme,
        title: String
    ) {
        self.theme = theme
        self.title = title
    }
    
    static func ==(lhs: TitleComponent, rhs: TitleComponent) -> Bool {
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.title != rhs.title {
            return false
        }
        return true
    }
    
    final class View: UIView {
        private let title = ComponentView<Empty>()
        
        private var component: TitleComponent?
        private weak var state: EmptyComponentState?

        override init(frame: CGRect) {
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func update(component: TitleComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            self.component = component
            self.state = state
            
            let titleSize = self.title.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: component.title, font: Font.semibold(17.0), textColor: component.theme.list.itemPrimaryTextColor))
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width, height: 100.0)
            )
            let titleFrame = CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: titleSize)
            if let titleView = self.title.view {
                if titleView.superview == nil {
                    titleView.isUserInteractionEnabled = false
                    self.addSubview(titleView)
                }
                titleView.frame = titleFrame
            }

            return titleSize
        }
    }
    
    func makeView() -> View {
        return View(frame: CGRect())
    }
    
    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}

private final class ActionButtonsComponent: Component {
    let theme: PresentationTheme
    let strings: PresentationStrings
    let actionTitle: String
    let action: (() -> Void)?
    
    init(
        theme: PresentationTheme,
        strings: PresentationStrings,
        actionTitle: String,
        action: (() -> Void)?
    ) {
        self.theme = theme
        self.strings = strings
        self.actionTitle = actionTitle
        self.action = action
    }
    
    static func ==(lhs: ActionButtonsComponent, rhs: ActionButtonsComponent) -> Bool {
        if lhs.theme !== rhs.theme {
            return false
        }
        if lhs.strings !== rhs.strings {
            return false
        }
        if lhs.actionTitle != rhs.actionTitle {
            return false
        }
        if (lhs.action == nil) != (rhs.action == nil) {
            return false
        }
        return true
    }
    
    final class View: UIView {
        private let actionButton = ComponentView<Empty>()

        private var component: ActionButtonsComponent?
        private weak var state: EmptyComponentState?

        override init(frame: CGRect) {
            super.init(frame: frame)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func update(component: ActionButtonsComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            self.component = component
            self.state = state
            
            let actionButtonWidth: CGFloat = availableSize.width
            
            var actionButtonContents: [AnyComponentWithIdentity<Empty>] = []
            actionButtonContents.append(AnyComponentWithIdentity(id: 0, component: AnyComponent(MultilineTextComponent(
                text: .plain(NSAttributedString(string: component.actionTitle, font: Font.semibold(17.0), textColor: component.theme.list.itemCheckColors.foregroundColor))
            ))))
            
            let actionButtonSize = self.actionButton.update(
                transition: transition,
                component: AnyComponent(ButtonComponent(
                    background: ButtonComponent.Background(
                        style: .glass,
                        color: component.theme.list.itemCheckColors.fillColor,
                        foreground: component.theme.list.itemCheckColors.foregroundColor,
                        pressedColor: component.theme.list.itemCheckColors.fillColor.withMultipliedAlpha(0.9)
                    ),
                    content: AnyComponentWithIdentity(
                        id: AnyHashable(0),
                        component: AnyComponent(HStack(
                            actionButtonContents,
                            spacing: 6.0
                        ))
                    ),
                    isEnabled: component.action != nil,
                    displaysProgress: false,
                    action: { [weak self] in
                        guard let self, let component = self.component else {
                            return
                        }
                        component.action?()
                    }
                )),
                environment: {},
                containerSize: CGSize(width: actionButtonWidth, height: availableSize.height)
            )
            let actionButtonFrame = CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: actionButtonSize)
            if let actionButtonView = self.actionButton.view {
                if actionButtonView.superview == nil {
                    self.addSubview(actionButtonView)
                }
                transition.setFrame(view: actionButtonView, frame: actionButtonFrame)
            }

            return CGSize(width: availableSize.width, height: actionButtonSize.height)
        }
    }
    
    func makeView() -> View {
        return View(frame: CGRect())
    }
    
    func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
