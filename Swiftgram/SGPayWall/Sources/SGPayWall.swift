import Foundation
import SwiftUI
import SGSwiftUI
import SGIAP
import TelegramPresentationData
import LegacyUI
import Display
import SGConfig
import SGStrings
import SwiftSignalKit
import TelegramUIPreferences


@available(iOS 13.0, *)
public func sgPayWallController(accountManager: AccountMana presentationData: PresentationData? = nil, SGIAPManager: SGIAPManager) -> ViewController {
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
    
    let statusSignal = accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.sgStatus])
    |> take(1)
    |> map { sharedData -> Int64 in
        if let sgStatus = sharedData.entries[ApplicationSpecificSharedDataKeys.sgStatus] as? SGStatus {
            return sgStatus.status
        } else {
            return SGStatus.default
        }
    }
    
    let swiftUIView = SGSwiftUIView<SGPayWallView>(
        legacyController: legacyController,
        content: {
            SGPayWallView(statusSignal: statusSignal, wrapperController: legacyController, SGIAP: SGIAPManager, lang: strings.baseLanguageCode)
        }
    )
    let controller = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
    legacyController.bind(controller: controller)
    
    return legacyController
}

private let innerShadowWidth: CGFloat = 15.0
private let accentColorHex: String = "F1552E"


@available(iOS 13.0, *)
struct BackgroundView: View {
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(hex: "A053F8").opacity(0.8), location: 0.0), // purple gradient
                    .init(color: Color.clear, location: 0.20),
                    
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .edgesIgnoringSafeArea(.all)
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color(hex: "CC4303").opacity(0.6), location: 0.0), // orange gradient
                    .init(color: Color.clear, location: 0.15),
                ]),
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            .blendMode(.lighten)
            
            .edgesIgnoringSafeArea(.all)
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Color.clear, lineWidth: 0)
                    .background(
                        ZStack {
                            innerShadow(x: -2, y: -2, blur: 4, color: Color(hex: "FF8C56")) // orange shadow
                            innerShadow(x: 2, y: 2, blur: 4, color: Color(hex: "A053F8")) // purple shadow
                            // innerShadow(x: 0, y: 0, blur: 4, color: Color.white.opacity(0.3))
                        }
                    )
            )
            .edgesIgnoringSafeArea(.all)
        }
        .background(Color.black)
    }
    
    func innerShadow(x: CGFloat, y: CGFloat, blur: CGFloat, color: Color) -> some View {
        return RoundedRectangle(cornerRadius: 0)
            .stroke(color, lineWidth: innerShadowWidth)
            .blur(radius: blur)
            .offset(x: x, y: y)
            .mask(RoundedRectangle(cornerRadius: 0).fill(LinearGradient(gradient: Gradient(colors: [Color.black, Color.clear]), startPoint: .top, endPoint: .bottom)))
    }
}


@available(iOS 13.0, *)
struct SGPayWallView: View {
    @Environment(\.navigationBarHeight) var navigationBarHeight: CGFloat
    @Environment(\.containerViewLayout) var containerViewLayout: ContainerViewLayout?
    
    weak var wrapperController: LegacyController?
    let SGIAP: SGIAPManager
    let lang: String
    
    // State management
    @State private var product: SGIAPManager.SGProduct?
    @State private var isRestoringPurchases = false
    
    private let productsPub = NotificationCenter.default.publisher(for: .SGIAPHelperProductsUpdatedNotification, object: nil)
    
    // Loading state enum
    private enum LoadingState {
        case loading
        case loaded
        case error(String)
    }
    
    var body: some View {
        ZStack {
            BackgroundView()
            
            ZStack(alignment: .bottom) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Icon
                        Image("pro")
                            .frame(width: 100, height: 100)
                        
                        // Title and Subtitle
                        VStack(spacing: 8) {
                            Text("Swiftgram Pro")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            
                            Text("Supercharged with Pro features")
                                .font(.callout)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        // Features
                        VStack(spacing: 8) {
                            featuresSection
                            restorePurchasesButton
                        }
                        
                        // Spacer for purchase buttons
                        Color.clear.frame(height: 50)
                    }
                    .padding(.vertical, 50)
                }
                
                // Fixed purchase button at bottom
                purchaseSection
            }
        }
        .overlay(closeButtonView)
        .colorScheme(.dark)
        .onReceive(productsPub) { _ in
            updateSelectedProduct()
        }
        .onAppear {
            updateSelectedProduct()
        }
    }
    
    private var featuresSection: some View {
        VStack(spacing: 8) {
            FeatureRow(
                icon: FeatureIcon(icon: "lock.fill", backgroundColor: .blue),
                title: "Session Backup",
                subtitle: "Restore sessions from encrypted local Apple Keychain backup."
            )
            
            FeatureRow(
                icon: FeatureIcon(icon: "nosign", backgroundColor: .gray, fontWeight: .bold),
                title: "Message Filter",
                subtitle: "Reduce visibility of spam, promotions and annoying messages."
            )
            
            FeatureRow(
                icon: FeatureIcon(icon: "bell.badge.slash.fill", backgroundColor: .red),
                title: "Disable @mentions and replies",
                subtitle: "Hide or silence non-important notifications."
            )
            
            FeatureRow(
                icon: FeatureIcon(icon: "bold.underline", backgroundColor: .blue, iconSize: 16),
                title: "Quick Formatting panel",
                subtitle: "Save time preparing your posts with a panel right above your keyboard."
            )
        }
        .padding(.leading, max(innerShadowWidth + 8.0, sgLeftSafeAreaInset(containerViewLayout)))
        .padding(.trailing, max(innerShadowWidth + 8.0, sgRightSafeAreaInset(containerViewLayout)))
    }
    
    private var restorePurchasesButton: some View {
        Button(action: handleRestorePurchases) {
            Text("Restore Purchases")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundColor(Color(hex: accentColorHex))
        }
        .disabled(isRestoringPurchases)
        .opacity(isRestoringPurchases ? 1.0 : 0.5)
    }
    
    private var purchaseSection: some View {
        VStack(spacing: 0) {
            Divider()
            
            Button(action: handlePurchase) {
                Text(buttonTitle)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(hex: accentColorHex))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(!canPurchase)
            .opacity(canPurchase ? 1.0 : 0.5)
            .padding([.horizontal, .top])
            .padding(.bottom, sgBottomSafeAreaInset(containerViewLayout))
        }
        .foregroundColor(Color.black)
        .backgroundIfAvailable(material: .ultraThinMaterial)
        .shadow(radius: 8, y: -4)
    }
    
    private var closeButtonView: some View {
        Button(action: dismiss) {
            Image(systemName: "xmark")
                .font(.headline)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding([.top, .trailing], 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
    
    // MARK: - Computed Properties
    
    private var buttonTitle: String {
        if let product = product {
            if !SGIAP.canMakePayments {
                return "Payments unavailable"
            } else {
                return "Subscribe for \(product.price) / month"
            }
        } else {
            return "Contacting App Store..."
        }
    }
    
    private var canPurchase: Bool {
        if !SGIAP.canMakePayments {
            return false
        } else {
            return product != nil
        }
    }
    
    // MARK: - Methods
    
    private func updateSelectedProduct() {
        product = SGIAP.availableProducts.first { $0.id == SG_CONFIG.iaps.first ?? "" }
    }
    
    private func handlePurchase() {
        guard let product = product else { return }
        SGIAP.buyProduct(product.skProduct)
    }
    
    private func handleRestorePurchases() {
        isRestoringPurchases = true
        SGIAP.restorePurchases {
            isRestoringPurchases = false
        }
    }
    
    private func dismiss() {
        wrapperController?.dismiss(animated: true)
    }
}


@available(iOS 13.0, *)
struct FeatureIcon: View {
    let icon: String
    let iconColor: Color
    let backgroundColor: Color
    let iconSize: CGFloat
    let frameSize: CGFloat
    let fontWeight: SwiftUI.Font.Weight
    
    init(
        icon: String,
        iconColor: Color = .white,
        backgroundColor: Color = .blue,
        iconSize: CGFloat = 18,
        frameSize: CGFloat = 32,
        fontWeight: SwiftUI.Font.Weight = .regular
    ) {
        self.icon = icon
        self.iconColor = iconColor
        self.backgroundColor = backgroundColor
        self.iconSize = iconSize
        self.frameSize = frameSize
        self.fontWeight = fontWeight
    }
    
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: iconSize))
            .fontWeightIfAvailable(fontWeight)
            .foregroundColor(iconColor)
            .frame(width: frameSize, height: frameSize)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}


@available(iOS 13.0, *)
struct FeatureRow: View {
    let icon: FeatureIcon
    let title: String
    let subtitle: String
    
    var body: some View {
        Button(action: {
            // TODO(swiftgram): Feature row clarification
        }) {
            HStack(spacing: 16) {
                
                HStack(alignment: .top, spacing: 12) {
                    icon
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                            .fontWeight(.medium)
                        
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
