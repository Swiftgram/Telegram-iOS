import Foundation
import UIKit
import Display
import SwiftSignalKit


public final class PlaygroundInfoTheme {
    public let buttonBackgroundColor: UIColor
    public let buttonTextColor: UIColor
    public let incomingFundsTitleColor: UIColor
    public let outgoingFundsTitleColor: UIColor
    
    public init(
        buttonBackgroundColor: UIColor,
        buttonTextColor: UIColor,
        incomingFundsTitleColor: UIColor,
        outgoingFundsTitleColor: UIColor
    ) {
        self.buttonBackgroundColor = buttonBackgroundColor
        self.buttonTextColor = buttonTextColor
        self.incomingFundsTitleColor = incomingFundsTitleColor
        self.outgoingFundsTitleColor = outgoingFundsTitleColor
    }
}

public final class PlaygroundTransactionTheme {
    public let descriptionBackgroundColor: UIColor
    public let descriptionTextColor: UIColor
    
    public init(
        descriptionBackgroundColor: UIColor,
        descriptionTextColor: UIColor
    ) {
        self.descriptionBackgroundColor = descriptionBackgroundColor
        self.descriptionTextColor = descriptionTextColor
    }
}

public final class PlaygroundSetupTheme {
    public let buttonFillColor: UIColor
    public let buttonForegroundColor: UIColor
    public let inputBackgroundColor: UIColor
    public let inputPlaceholderColor: UIColor
    public let inputTextColor: UIColor
    public let inputClearButtonColor: UIColor
    
    public init(
        buttonFillColor: UIColor,
        buttonForegroundColor: UIColor,
        inputBackgroundColor: UIColor,
        inputPlaceholderColor: UIColor,
        inputTextColor: UIColor,
        inputClearButtonColor: UIColor
    ) {
        self.buttonFillColor = buttonFillColor
        self.buttonForegroundColor = buttonForegroundColor
        self.inputBackgroundColor = inputBackgroundColor
        self.inputPlaceholderColor = inputPlaceholderColor
        self.inputTextColor = inputTextColor
        self.inputClearButtonColor = inputClearButtonColor
    }
}

public final class PlaygroundListTheme {
    public let itemPrimaryTextColor: UIColor
    public let itemSecondaryTextColor: UIColor
    public let itemPlaceholderTextColor: UIColor
    public let itemDestructiveColor: UIColor
    public let itemAccentColor: UIColor
    public let itemDisabledTextColor: UIColor
    public let plainBackgroundColor: UIColor
    public let blocksBackgroundColor: UIColor
    public let itemPlainSeparatorColor: UIColor
    public let itemBlocksBackgroundColor: UIColor
    public let itemBlocksSeparatorColor: UIColor
    public let itemHighlightedBackgroundColor: UIColor
    public let sectionHeaderTextColor: UIColor
    public let freeTextColor: UIColor
    public let freeTextErrorColor: UIColor
    public let inputClearButtonColor: UIColor
    
    public init(
        itemPrimaryTextColor: UIColor,
        itemSecondaryTextColor: UIColor,
        itemPlaceholderTextColor: UIColor,
        itemDestructiveColor: UIColor,
        itemAccentColor: UIColor,
        itemDisabledTextColor: UIColor,
        plainBackgroundColor: UIColor,
        blocksBackgroundColor: UIColor,
        itemPlainSeparatorColor: UIColor,
        itemBlocksBackgroundColor: UIColor,
        itemBlocksSeparatorColor: UIColor,
        itemHighlightedBackgroundColor: UIColor,
        sectionHeaderTextColor: UIColor,
        freeTextColor: UIColor,
        freeTextErrorColor: UIColor,
        inputClearButtonColor: UIColor
    ) {
        self.itemPrimaryTextColor = itemPrimaryTextColor
        self.itemSecondaryTextColor = itemSecondaryTextColor
        self.itemPlaceholderTextColor = itemPlaceholderTextColor
        self.itemDestructiveColor = itemDestructiveColor
        self.itemAccentColor = itemAccentColor
        self.itemDisabledTextColor = itemDisabledTextColor
        self.plainBackgroundColor = plainBackgroundColor
        self.blocksBackgroundColor = blocksBackgroundColor
        self.itemPlainSeparatorColor = itemPlainSeparatorColor
        self.itemBlocksBackgroundColor = itemBlocksBackgroundColor
        self.itemBlocksSeparatorColor = itemBlocksSeparatorColor
        self.itemHighlightedBackgroundColor = itemHighlightedBackgroundColor
        self.sectionHeaderTextColor = sectionHeaderTextColor
        self.freeTextColor = freeTextColor
        self.freeTextErrorColor = freeTextErrorColor
        self.inputClearButtonColor = inputClearButtonColor
    }
}

public final class PlaygroundTheme: Equatable {
    public let info: PlaygroundInfoTheme
    public let transaction: PlaygroundTransactionTheme
    public let setup: PlaygroundSetupTheme
    public let list: PlaygroundListTheme
    public let statusBarStyle: StatusBarStyle
    public let navigationBar: NavigationBarTheme
    public let keyboardAppearance: UIKeyboardAppearance
    public let alert: AlertControllerTheme
    public let actionSheet: ActionSheetControllerTheme
    
    private let resourceCache = PlaygroundThemeResourceCache()
    
    public init(info: PlaygroundInfoTheme, transaction: PlaygroundTransactionTheme, setup: PlaygroundSetupTheme, list: PlaygroundListTheme, statusBarStyle: StatusBarStyle, navigationBar: NavigationBarTheme, keyboardAppearance: UIKeyboardAppearance, alert: AlertControllerTheme, actionSheet: ActionSheetControllerTheme) {
        self.info = info
        self.transaction = transaction
        self.setup = setup
        self.list = list
        self.statusBarStyle = statusBarStyle
        self.navigationBar = navigationBar
        self.keyboardAppearance = keyboardAppearance
        self.alert = alert
        self.actionSheet = actionSheet
    }
    
    func image(_ key: Int32, _ generate: (PlaygroundTheme) -> UIImage?) -> UIImage? {
        return self.resourceCache.image(key, self, generate)
    }
    
    public static func ==(lhs: PlaygroundTheme, rhs: PlaygroundTheme) -> Bool {
        return lhs === rhs
    }
}


private final class PlaygroundThemeResourceCacheHolder {
    var images: [Int32: UIImage] = [:]
}

private final class PlaygroundThemeResourceCache {
    private let imageCache = Atomic<PlaygroundThemeResourceCacheHolder>(value: PlaygroundThemeResourceCacheHolder())
    
    public func image(_ key: Int32, _ theme: PlaygroundTheme, _ generate: (PlaygroundTheme) -> UIImage?) -> UIImage? {
        let result = self.imageCache.with { holder -> UIImage? in
            return holder.images[key]
        }
        if let result = result {
            return result
        } else {
            if let image = generate(theme) {
                self.imageCache.with { holder -> Void in
                    holder.images[key] = image
                }
                return image
            } else {
                return nil
            }
        }
    }
}

enum PlaygroundThemeResourceKey: Int32 {
    case itemListCornersBoth
    case itemListCornersTop
    case itemListCornersBottom
    case itemListClearInputIcon
    case itemListDisclosureArrow
    case navigationShareIcon
    case transactionLockIcon
    
    case clockMin
    case clockFrame
}

func cornersImage(_ theme: PlaygroundTheme, top: Bool, bottom: Bool) -> UIImage? {
    if !top && !bottom {
        return nil
    }
    let key: PlaygroundThemeResourceKey
    if top && bottom {
        key = .itemListCornersBoth
    } else if top {
        key = .itemListCornersTop
    } else {
        key = .itemListCornersBottom
    }
    return theme.image(key.rawValue, { theme in
        return generateImage(CGSize(width: 50.0, height: 50.0), rotatedContext: { (size, context) in
            let bounds = CGRect(origin: CGPoint(), size: size)
            context.setFillColor(theme.list.blocksBackgroundColor.cgColor)
            context.fill(bounds)
            
            context.setBlendMode(.clear)
            
            var corners: UIRectCorner = []
            if top {
                corners.insert(.topLeft)
                corners.insert(.topRight)
            }
            if bottom {
                corners.insert(.bottomLeft)
                corners.insert(.bottomRight)
            }
            let path = UIBezierPath(roundedRect: bounds, byRoundingCorners: corners, cornerRadii: CGSize(width: 11.0, height: 11.0))
            context.addPath(path.cgPath)
            context.fillPath()
        })?.stretchableImage(withLeftCapWidth: 25, topCapHeight: 25)
    })
}

func itemListClearInputIcon(_ theme: PlaygroundTheme) -> UIImage? {
    return theme.image(PlaygroundThemeResourceKey.itemListClearInputIcon.rawValue, { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Playground/ClearInput"), color: theme.list.inputClearButtonColor)
    })
}

func navigationShareIcon(_ theme: PlaygroundTheme) -> UIImage? {
    return theme.image(PlaygroundThemeResourceKey.navigationShareIcon.rawValue, { theme in
        generateTintedImage(image: UIImage(bundleImageName: "Playground/NavigationShare"), color: theme.navigationBar.buttonColor)
    })
}

func disclosureArrowImage(_ theme: PlaygroundTheme) -> UIImage? {
    return theme.image(PlaygroundThemeResourceKey.itemListDisclosureArrow.rawValue, { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Playground/DisclosureArrow"), color: theme.list.itemSecondaryTextColor)
    })
}

func clockFrameImage(_ theme: PlaygroundTheme) -> UIImage? {
    return theme.image(PlaygroundThemeResourceKey.clockFrame.rawValue, { theme in
        let color = theme.list.itemSecondaryTextColor
        return generateImage(CGSize(width: 11.0, height: 11.0), contextGenerator: { size, context in
            context.clear(CGRect(origin: CGPoint(), size: size))
            context.setStrokeColor(color.cgColor)
            context.setFillColor(color.cgColor)
            let strokeWidth: CGFloat = 1.0
            context.setLineWidth(strokeWidth)
            context.strokeEllipse(in: CGRect(x: strokeWidth / 2.0, y: strokeWidth / 2.0, width: size.width - strokeWidth, height: size.height - strokeWidth))
            context.fill(CGRect(x: (11.0 - strokeWidth) / 2.0, y: strokeWidth * 3.0, width: strokeWidth, height: 11.0 / 2.0 - strokeWidth * 3.0))
        })
    })
}

func clockMinImage(_ theme: PlaygroundTheme) -> UIImage? {
    return theme.image(PlaygroundThemeResourceKey.clockMin.rawValue, { theme in
        let color = theme.list.itemSecondaryTextColor
        return generateImage(CGSize(width: 11.0, height: 11.0), contextGenerator: { size, context in
            context.clear(CGRect(origin: CGPoint(), size: size))
            context.setFillColor(color.cgColor)
            let strokeWidth: CGFloat = 1.0
            context.fill(CGRect(x: (11.0 - strokeWidth) / 2.0, y: (11.0 - strokeWidth) / 2.0, width: 11.0 / 2.0 - strokeWidth, height: strokeWidth))
        })
    })
}

func PlaygroundTransactionLockIcon(_ theme: PlaygroundTheme) -> UIImage? {
    return theme.image(PlaygroundThemeResourceKey.transactionLockIcon.rawValue, { theme in
        return generateTintedImage(image: UIImage(bundleImageName: "Playground/EncryptedComment"), color: theme.list.itemSecondaryTextColor)
    })
}


public let ACCENT_COLOR = UIColor(rgb: 0x007ee5)
public let NAVIGATION_BAR_THEME = NavigationBarTheme(
    buttonColor: ACCENT_COLOR,
    disabledButtonColor: UIColor(rgb: 0xd0d0d0),
    primaryTextColor: .black,
    backgroundColor: UIColor(rgb: 0xf7f7f7),
    enableBackgroundBlur: true,
    separatorColor: UIColor(rgb: 0xb1b1b1),
    badgeBackgroundColor: UIColor(rgb: 0xff3b30),
    badgeStrokeColor: UIColor(rgb: 0xff3b30),
    badgeTextColor: .white
)
public let THEME = PlaygroundTheme(
    info: PlaygroundInfoTheme(
        buttonBackgroundColor: UIColor(rgb: 0x32aafe),
        buttonTextColor: .white,
        incomingFundsTitleColor: UIColor(rgb: 0x00b12c),
        outgoingFundsTitleColor: UIColor(rgb: 0xff3b30)
    ), transaction: PlaygroundTransactionTheme(
        descriptionBackgroundColor: UIColor(rgb: 0xf1f1f4),
        descriptionTextColor: .black
    ), setup: PlaygroundSetupTheme(
        buttonFillColor: ACCENT_COLOR,
        buttonForegroundColor: .white,
        inputBackgroundColor: UIColor(rgb: 0xe9e9e9),
        inputPlaceholderColor: UIColor(rgb: 0x818086),
        inputTextColor: .black,
        inputClearButtonColor: UIColor(rgb: 0x7b7b81).withAlphaComponent(0.8)
    ),
    list: PlaygroundListTheme(
        itemPrimaryTextColor: .black,
        itemSecondaryTextColor: UIColor(rgb: 0x8e8e93),
        itemPlaceholderTextColor: UIColor(rgb: 0xc8c8ce),
        itemDestructiveColor: UIColor(rgb: 0xff3b30),
        itemAccentColor: ACCENT_COLOR,
        itemDisabledTextColor: UIColor(rgb: 0x8e8e93),
        plainBackgroundColor: .white,
        blocksBackgroundColor: UIColor(rgb: 0xefeff4),
        itemPlainSeparatorColor: UIColor(rgb: 0xc8c7cc),
        itemBlocksBackgroundColor: .white,
        itemBlocksSeparatorColor: UIColor(rgb: 0xc8c7cc),
        itemHighlightedBackgroundColor: UIColor(rgb: 0xe5e5ea),
        sectionHeaderTextColor: UIColor(rgb: 0x6d6d72),
        freeTextColor: UIColor(rgb: 0x6d6d72),
        freeTextErrorColor: UIColor(rgb: 0xcf3030),
        inputClearButtonColor: UIColor(rgb: 0xcccccc)
    ),
    statusBarStyle: .Black,
    navigationBar: NAVIGATION_BAR_THEME,
    keyboardAppearance: .light,
    alert: AlertControllerTheme(
        backgroundType: .light,
        backgroundColor: .white,
        separatorColor: UIColor(white: 0.9, alpha: 1.0),
        highlightedItemColor: UIColor(rgb: 0xe5e5ea),
        primaryColor: .black,
        secondaryColor: UIColor(rgb: 0x5e5e5e),
        accentColor: ACCENT_COLOR,
        contrastColor: .green,
        destructiveColor: UIColor(rgb: 0xff3b30),
        disabledColor: UIColor(rgb: 0xd0d0d0),
        controlBorderColor: .green,
        baseFontSize: 17.0
    ),
    actionSheet: ActionSheetControllerTheme(
        dimColor: UIColor(white: 0.0, alpha: 0.4),
        backgroundType: .light,
        itemBackgroundColor: .white,
        itemHighlightedBackgroundColor: UIColor(white: 0.9, alpha: 1.0),
        standardActionTextColor: ACCENT_COLOR,
        destructiveActionTextColor: UIColor(rgb: 0xff3b30),
        disabledActionTextColor: UIColor(rgb: 0xb3b3b3),
        primaryTextColor: .black,
        secondaryTextColor: UIColor(rgb: 0x5e5e5e),
        controlAccentColor: ACCENT_COLOR,
        controlColor: UIColor(rgb: 0x7e8791),
        switchFrameColor: UIColor(rgb: 0xe0e0e0),
        switchContentColor: UIColor(rgb: 0x77d572),
        switchHandleColor: UIColor(rgb: 0xffffff),
        baseFontSize: 17.0
    )
)
