import Foundation
import SwiftUI
import SGSwiftUI
import SGStrings
import SGSimpleSettings
import LegacyUI
import Display
import TelegramPresentationData
import AccountContext


struct Badge: Identifiable, Hashable {
    let id: UUID = .init()
    let displayName: String
    let assetName: String
}

let badges: [Badge] = [
    .init(displayName: "Swiftgram", assetName: "swiftgram"),
    .init(displayName: "Telegram",   assetName: "telegram"),
    .init(displayName: "Code Red",   assetName: "code_red"),
    .init(displayName: "Silver",   assetName: "silver"),
    .init(displayName: "Russian",   assetName: "russian"),
    .init(displayName: "None",   assetName: "none"),
]

public class BadgeMabager {
    public static func getBadgeImage() -> UIImage {
        if SGSimpleSettings.shared.selectedBadgeName == "none" {
            return UIImage()
        }
        for badge in badges {
            if badge.assetName == SGSimpleSettings.shared.selectedBadgeName {
                return UIImage(named: badge.assetName)!
            }
        }
        return UIImage(named: badges.first!.assetName)!
    }
}
    
@available(iOS 14.0, *)
struct BadgeSettingsView: View {
    weak var wrapperController: LegacyController?
    let context: AccountContext
    
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.lang) var lang: String
    
    @State var selectedBadge: Badge

    private enum Layout {
        static let cardCorner: CGFloat = 12
        static let imageHeight: CGFloat = 56
        static let columnSpacing: CGFloat = 16
        static let horizontalPadding: CGFloat = 20
    }

    private var columns: [SwiftUI.GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Layout.columnSpacing), count: 2)
    }
    
    init(wrapperController: LegacyController?, context: AccountContext) {
        self.wrapperController = wrapperController
        self.context = context
        
        for badge in badges {
            if badge.assetName == SGSimpleSettings.shared.selectedBadgeName {
                self._selectedBadge = State(initialValue: badge)
                return
            }
        }
        
        self._selectedBadge = State(initialValue: badges.first!)
    }
    
    private func onSelectBadge(_ badge: Badge) {
        self.selectedBadge = badge
        SGSimpleSettings.shared.selectedBadgeName = selectedBadge.assetName
        if badge.assetName != "none" {
            self.context.sharedContext.mainWindow?.badgeView.image = UIImage(named: badge.assetName)
        } else {
            self.context.sharedContext.mainWindow?.badgeView.image = UIImage()
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .center, spacing: Layout.columnSpacing) {
                ForEach(badges) { badge in
                    Button {
                        onSelectBadge(badge)
                    } label: {
                        VStack(spacing: 8) {
                            Image(badge.assetName)
                                .resizable()
                                .scaledToFit()
                                .frame(height: Layout.imageHeight)
                                .accessibilityHidden(true)

                            Text(badge.displayName)
                                .font(.body)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(colorScheme == .dark ? .secondarySystemBackground : .systemBackground))
                        .cornerRadius(Layout.cardCorner)
                        .overlay(
                            RoundedRectangle(cornerRadius: Layout.cardCorner)
                                .stroke(selectedBadge == badge ? Color.accentColor : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, 24)

        }
        .background(Color(colorScheme == .light ? .secondarySystemBackground : .systemBackground).ignoresSafeArea())
    }
    
}

@available(iOS 14.0, *)
public func sgBadgeSettingsController(context: AccountContext, presentationData: PresentationData? = nil) -> ViewController {
    let theme = presentationData?.theme ?? (UITraitCollection.current.userInterfaceStyle == .dark ? defaultDarkColorPresentationTheme : defaultPresentationTheme)
    let strings = presentationData?.strings ?? defaultPresentationStrings

    let legacyController = LegacySwiftUIController(
        presentation: .navigation,
        theme: theme,
        strings: strings
    )

    legacyController.statusBar.statusBarStyle = theme.rootController
        .statusBarStyle.style
    legacyController.title = "AppBadges.Title".i18n(strings.baseLanguageCode)
    
    let swiftUIView = SGSwiftUIView<BadgeSettingsView>(
        legacyController: legacyController,
        manageSafeArea: true,
        content: {
            BadgeSettingsView(wrapperController: legacyController, context: context)
        }
    )
    let controller = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
    legacyController.bind(controller: controller)

    return legacyController
}
