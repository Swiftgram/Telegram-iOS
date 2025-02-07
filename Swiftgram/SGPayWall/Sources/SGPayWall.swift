import Foundation
import SwiftUI
import SGSwiftUI
import SGIAP
import TelegramPresentationData
import LegacyUI
import Display
import SGConfig
// import SGStrings


struct SGPerk: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let icon: String
}



@available(iOS 13.0, *)
struct SGPayWallView: View {
    
    weak var wrapperController: LegacyController?
    let SGIAP: SGIAPManager
    
    let perks = [
        SGPerk(title: "Premium Features", description: "Access all premium features and tools", icon: "star.fill"),
        SGPerk(title: "No Ads", description: "Enjoy an ad-free experience", icon: "banner.slash"),
        SGPerk(title: "Cloud Sync", description: "Sync your data across all devices", icon: "cloud.fill"),
        SGPerk(title: "Priority Support", description: "Get priority customer support", icon: "questionmark.circle.fill"),
        SGPerk(title: "Advanced Stats", description: "Access detailed analytics and insights", icon: "chart.bar.fill"),
        SGPerk(title: "Premium Features", description: "Access all premium features and tools", icon: "star.fill"),
        SGPerk(title: "No Ads", description: "Enjoy an ad-free experience", icon: "banner.slash"),
        SGPerk(title: "Cloud Sync", description: "Sync your data across all devices", icon: "cloud.fill"),
        SGPerk(title: "Priority Support", description: "Get priority customer support", icon: "questionmark.circle.fill"),
        SGPerk(title: "Advanced Stats", description: "Access detailed analytics and insights", icon: "chart.bar.fill"),
        SGPerk(title: "Advanced Stats", description: "Access detailed analytics and insights", icon: "chart.bar.fill"),
        SGPerk(title: "Premium Features", description: "Access all premium features and tools", icon: "star.fill"),
        SGPerk(title: "No Ads", description: "Enjoy an ad-free experience", icon: "banner.slash"),
        SGPerk(title: "Cloud Sync", description: "Sync your data across all devices", icon: "cloud.fill"),
        SGPerk(title: "Priority Support", description: "Get priority customer support", icon: "questionmark.circle.fill"),
        SGPerk(title: "Advanced Stats", description: "Access detailed analytics and insights", icon: "chart.bar.fill"),
    ]
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        ForEach(perks) { perk in
                            HStack(spacing: 16) {
                                Image(systemName: perk.icon)
                                    .font(.title)
                                    .foregroundColor(.blue)
                                    .frame(width: 32)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(perk.title)
                                        .font(.headline)
                                    Text(perk.description)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical, 24)
                }
                
                VStack(spacing: 12) {
                    Button(action: {
                        for availableProduct in SGIAP.availableProducts {
                            if SG_CONFIG.iaps.contains(availableProduct.skProduct.productIdentifier ) {
                                SGIAP.purchaseProduct(availableProduct, completion: { _ in })
                            }
                        }
                        SGIAP.buyProduct(product: product)
                    }) {
                        Text("Unlock Premium - $9.99")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(16)
                    }
                    
                    Button(action: {
                        SGIAP.restorePurchases(completion: { _ in })
                    }) {
                        Text("Restore Purchases")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                }
                .padding(24)
                .background(
                    Rectangle()
                        .fill(Color(UIColor.systemBackground))
                        .shadow(radius: 8, y: -4)
                )
            }.navigationBarItems(trailing: closeButtonView)
            
        }
        .colorScheme(.dark)
    }
    
    private var closeButtonView: some View {
        Button(action: {
            wrapperController?.dismiss(animated: true)
        }) {
            if #available(iOS 15.0, *) {
                Image(systemName: "xmark.circle.fill")
                    .font(.headline)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
        }
    }
}



@available(iOS 13.0, *)
public func sgPayWallController(presentationData: PresentationData? = nil, SGIAPManager: SGIAPManager) -> ViewController {
    //    let theme = presentationData?.theme ?? (UITraitCollection.current.userInterfaceStyle == .dark ? defaultDarkColorPresentationTheme : defaultPresentationTheme)
    let theme = defaultDarkColorPresentationTheme
    let strings = presentationData?.strings ?? defaultPresentationStrings
    
    let legacyController = LegacySwiftUIController(
        presentation: .modal(animateIn: true),
        theme: theme,
        strings: strings
    )
    //    legacyController.displayNavigationBar = false
    legacyController.statusBar.statusBarStyle = .White
    legacyController.attemptNavigation = { _ in return false }
    let swiftUIView = SGPayWallView(wrapperController: legacyController, SGIAP: SGIAPManager)
    let controller = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
    legacyController.bind(controller: controller)
    
    return legacyController
}
