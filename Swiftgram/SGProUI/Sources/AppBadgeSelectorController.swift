import Foundation
import SwiftUI
import SGSwiftUI
import SGStrings
import SGSimpleSettings
import Display
import TelegramPresentationData
import AccountContext


struct AppBadge: Identifiable, Hashable {
    let id: UUID = .init()
    let displayName: String
    let assetName: String
}

func getAvailableAppBadges() -> [AppBadge] {
    var appBadges: [AppBadge] = [
        .init(displayName: "Default", assetName: "Components/AppBadge"),
        .init(displayName: "Sky", assetName: "SkyAppBadge"),
        .init(displayName: "Night", assetName: "NightAppBadge"),
        .init(displayName: "Titanium", assetName: "TitaniumAppBadge"),
        .init(displayName: "Pro", assetName: "ProAppBadge"),
        .init(displayName: "Day", assetName: "DayAppBadge"),
    ]

    if SGSimpleSettings.shared.duckyAppIconAvailable {
        appBadges.append(.init(displayName: "Ducky", assetName: "DuckyAppBadge"))
    }
    appBadges += [
        .init(displayName: "Sparkling", assetName: "SparklingAppBadge"),
    ]

    return appBadges
}
    
struct AppBadgeSettingsView: View {
    let context: AccountContext
    
    @Environment(\.sgTheme) private var theme
    @Environment(\.lang) var lang: String
    
    @State var selectedBadge: AppBadge
    let availableAppBadges: [AppBadge] = getAvailableAppBadges()

    private enum Layout {
        static let cardCorner: CGFloat = 12
        static let imageHeight: CGFloat = 56
        static let columnSpacing: CGFloat = 16
        static let horizontalPadding: CGFloat = 20
    }

    private var columns: [SwiftUI.GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Layout.columnSpacing), count: 2)
    }
    
    init(context: AccountContext) {
        self.context = context
        
        for badge in self.availableAppBadges {
            if badge.assetName == SGSimpleSettings.shared.customAppBadge {
                self._selectedBadge = State(initialValue: badge)
                return
            }
        }
        
        self._selectedBadge = State(initialValue: self.availableAppBadges.first!)
    }
    
    private func onSelectBadge(_ badge: AppBadge) {
        self.selectedBadge = badge
        let image = UIImage(bundleImageName: selectedBadge.assetName) ?? UIImage(bundleImageName: "Components/AppBadge")
        if self.context.sharedContext.immediateSGStatus.status > 1 {
            DispatchQueue.main.async {
                SGSimpleSettings.shared.customAppBadge = selectedBadge.assetName
                self.context.sharedContext.mainWindow?.badgeView.image = image
            }
        }
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .center, spacing: Layout.columnSpacing) {
                ForEach(availableAppBadges) { badge in
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
                                .font(.footnote)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(theme.secondaryBackgroundColor)
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
        .background(theme.backgroundColor.ignoresSafeArea())
        .sgNavigationTitle("AppBadge.Title".i18n(lang))
    }
    
}

public func sgAppBadgeSettingsController(context: AccountContext, presentationData: PresentationData? = nil) -> ViewController {
    let presentationData = presentationData ?? context.sharedContext.currentPresentationData.with { $0 }
    return SGSwiftUIController(
        title: "AppBadge.Title".i18n(presentationData.strings.baseLanguageCode),
        presentationData: presentationData,
        presentationDataSignal: context.sharedContext.presentationData
    ) {
        AppBadgeSettingsView(context: context)
    }
}
