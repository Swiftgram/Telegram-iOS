import Foundation
import SwiftUI
import StoreKit
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
public func sgPayWallController(statusSignal: Signal<Int64, NoError>, replacementController: ViewController, presentationData: PresentationData? = nil, SGIAPManager: SGIAPManager, openUrl: @escaping (String, Bool) -> Void /* url, forceExternal */, paymentsEnabled: Bool, canBuyInBeta: Bool, openAppStorePage: @escaping () -> Void, proSupportUrl: String?) -> ViewController {
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
    legacyController.view.disablesInteractiveTransitionGestureRecognizer = true
    
    let swiftUIView = SGSwiftUIView<SGPayWallView>(
        legacyController: legacyController,
        content: {
            SGPayWallView(wrapperController: legacyController, replacementController: replacementController, SGIAP: SGIAPManager, statusSignal: statusSignal, openUrl: openUrl, openAppStorePage: openAppStorePage, paymentsEnabled: paymentsEnabled, canBuyInBeta: canBuyInBeta, proSupportUrl: proSupportUrl)
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
struct SGPayWallFeatureDetails: View {
    
    let dismissAction: () -> Void
    var bottomOffset: CGFloat = 0.0
    let contentHeight: CGFloat = 690.0
    let features: [SGProFeature]
    
    @State var shownFeature: SGProFeatureId?
     // Add animation states
    @State private var showBackground = false
    @State private var showContent = false
    
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background overlay
            if showBackground {
                Color.black.opacity(0.4)
                    .zIndex(0)
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        dismissWithAnimation()
                    }
                    .transition(.opacity)
            }
            
            // Bottom sheet content
            if showContent {
                VStack {
                    if #available(iOS 14.0, *) {
                        TabView(selection: $shownFeature) {
                            ForEach(features) { feature in
                                ScrollView(showsIndicators: false) {
                                    SGProFeatureView(
                                        feature: feature
                                    )
                                    Color.clear.frame(height: 8.0) // paginator padding
                                }
                                .tag(feature.id)
                                .scrollBounceBehaviorIfAvailable(.basedOnSize)
                            }
                        }
                        .tabViewStyle(.page)
                        .padding(.bottom, bottomOffset - 8.0)
                    }
                    
                    // Spacer for purchase buttons
                    if !bottomOffset.isZero {
                        Color.clear.frame(height: bottomOffset)
                    }
                }
                .zIndex(1)
                .frame(maxHeight: contentHeight)
                .background(Color(.black))
                .cornerRadius(8, corners: [.topLeft, .topRight])
                .overlay(closeButtonView)
                .offset(y: max(0, dragOffset))
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Only track downward movement
                            if value.translation.height > 0 {
                                dragOffset = value.translation.height
                            }
                        }
                        .onEnded { value in
                            // If dragged down more than 150 points or with significant velocity, dismiss
                            if value.translation.height > 150 || value.predictedEndTranslation.height > 200 {
                                dismissWithAnimation()
                            } else {
                                // Otherwise, reset position
                                withAnimation(.spring()) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
                .transition(.move(edge: .bottom))
            }
        }
        .onAppear {
            appearWithAnimation()
        }
    }
    
    private func appearWithAnimation() {
        withAnimation(.easeIn(duration: 0.2)) {
            showBackground = true
        }
        
        withAnimation(.spring(duration: 0.3)/*.delay(0.1)*/) {
            showContent = true
        }
    }
    
    private func dismissWithAnimation() {
        withAnimation(.spring()) {
            showContent = false
            dragOffset = 0
        }
        
        withAnimation(.easeOut(duration: 0.2).delay(0.1)) {
            showBackground = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            dismissAction()
        }
    }
    
    private var closeButtonView: some View {
        Button(action: {
            dismissWithAnimation()
        }) {
            Image(systemName: "xmark")
                .font(.headline)
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle()) // Improve tappable area
        }
        .opacity(showContent ? 1.0 : 0.0)
        .padding([.top, .trailing], 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}


@available(iOS 13.0, *)
struct SGProFeatureView: View {
    let feature: SGProFeature
    
    var body: some View {
        VStack(spacing: 16) {
            feature.image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 400.0, alignment: .top)
                .clipped()
            
            VStack(alignment: .center, spacing: 8) {
                Text(feature.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                Text(featureSubtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            Spacer()
        }
    }
    
    var featureSubtitle: String {
        return feature.description ?? feature.subtitle
    }
}

enum SGProFeatureId: Hashable {
    case backup
    case filter
    case notifications
    case toolbar
    case icons
}


@available(iOS 13.0, *)
struct SGProFeature: Identifiable {
    
    let id: SGProFeatureId
    let title: String
    let subtitle: String
    let description: String?
    
    @ViewBuilder
    public var icon: some View {
        switch (id) {
        case .backup:
            FeatureIcon(icon: "lock.fill", backgroundColor: .blue)
        case .filter:
            FeatureIcon(icon: "nosign", backgroundColor: .gray, fontWeight: .bold)
        case .notifications:
            FeatureIcon(icon: "bell.badge.slash.fill", backgroundColor: .red)
        case .toolbar:
            FeatureIcon(icon: "bold.underline", backgroundColor: .blue, iconSize: 16)
        case .icons:
            Image("SwiftgramSettings")
                .resizable()
                .frame(width: 32, height: 32)
        @unknown default:
            Image("SwiftgramPro")
                .resizable()
                .frame(width: 32, height: 32)
        }
    }

    public var image: Image {
        switch (id) {
        case .backup:
            return Image("ProDetailsBackup")
        case .filter:
            return Image("ProDetailsFilter")
        case .notifications:
            return Image("ProDetailsMute")
        case .toolbar:
            return Image("ProDetailsFormatting")
        case .icons:
            return Image("ProDetailsIcons")
        @unknown default:
            return Image("pro")
        }
    }
}


@available(iOS 13.0, *)
struct SGPayWallView: View {
    @Environment(\.navigationBarHeight) var navigationBarHeight: CGFloat
    @Environment(\.containerViewLayout) var containerViewLayout: ContainerViewLayout?
    @Environment(\.lang) var lang: String
    
    weak var wrapperController: LegacyController?
    let replacementController: ViewController
    let SGIAP: SGIAPManager
    let statusSignal: Signal<Int64, NoError>
    let openUrl: (String, Bool) -> Void // url, forceExternal
    let openAppStorePage: () -> Void
    let paymentsEnabled: Bool
    let canBuyInBeta: Bool
    let proSupportUrl: String?
    
    private enum PayWallState: Equatable {
        case ready // ready to buy
        case restoring
        case purchasing
        case validating
    }
    
    // State management
    @State private var product: SGIAPManager.SGProduct?
    @State private var currentStatus: Int64 = 1
    @State private var state: PayWallState = .ready
    @State private var showErrorAlert: Bool = false
    @State private var showConfetti: Bool = false
    @State private var showDetails: Bool = false
    @State private var shownFeature: SGProFeatureId? = nil
    
    private let productsPub = NotificationCenter.default.publisher(for: .SGIAPHelperProductsUpdatedNotification, object: nil)
    private let buyOrRestoreSuccessPub = NotificationCenter.default.publisher(for: .SGIAPHelperPurchaseNotification, object: nil)
    private let buyErrorPub = NotificationCenter.default.publisher(for: .SGIAPHelperErrorNotification, object: nil)
    private let validationErrorPub = NotificationCenter.default.publisher(for: .SGIAPHelperValidationErrorNotification, object: nil)
    
    @State private var statusTask: Task<Void, Never>? = nil
    
    @State private var hapticFeedback: HapticFeedback?
    private let confettiDuration: Double = 5.0
    
    @State private var purchaseSectionSize: CGSize = .zero
    
    private var features: [SGProFeature]  {
        return [
            SGProFeature(id: .backup, title: "PayWall.SessionBackup.Title".i18n(lang), subtitle: "PayWall.SessionBackup.Notice".i18n(lang), description: "PayWall.SessionBackup.Description".i18n(lang)),
            SGProFeature(id: .filter, title: "PayWall.MessageFilter.Title".i18n(lang), subtitle: "PayWall.MessageFilter.Notice".i18n(lang), description: "PayWall.MessageFilter.Description".i18n(lang)),
            SGProFeature(id: .notifications, title: "PayWall.Notifications.Title".i18n(lang), subtitle: "PayWall.Notifications.Notice".i18n(lang), description: "PayWall.Notifications.Description".i18n(lang)),
            SGProFeature(id: .toolbar, title: "PayWall.InputToolbar.Title".i18n(lang), subtitle: "PayWall.InputToolbar.Notice".i18n(lang), description: "PayWall.InputToolbar.Description".i18n(lang)),
            SGProFeature(id: .icons, title: "PayWall.AppIcons.Title".i18n(lang), subtitle: "PayWall.AppIcons.Notice".i18n(lang), description: nil)
        ]
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
                            
                            Text("PayWall.Text".i18n(lang))
                                .font(.callout)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        // Features
                        VStack(spacing: 36) {
                            featuresSection
                            
                            aboutSection
                            
                            VStack(spacing: 8) {
                                HStack {
                                    legalSection
                                    Spacer()
                                }
                                
                                HStack {
                                    restorePurchasesButton
                                    Spacer()
                                }
                            }
                    }
                        
                        
                        // Spacer for purchase buttons
                        Color.clear.frame(height: (purchaseSectionSize.height / 2.0))
                    }
                    .padding(.vertical, (purchaseSectionSize.height / 2.0))
                }
                .padding(.leading, max(innerShadowWidth + 8.0, sgLeftSafeAreaInset(containerViewLayout)))
                .padding(.trailing, max(innerShadowWidth + 8.0, sgRightSafeAreaInset(containerViewLayout)))
                
                if showDetails {
                    SGPayWallFeatureDetails(
                        dismissAction: dismissDetails,
                        bottomOffset: (purchaseSectionSize.height / 2.0)  * 0.9, // reduced offset for paginator
                        features: features,
                        shownFeature: shownFeature)
                }

                // Fixed purchase button at bottom
                purchaseSection
                    .trackSize($purchaseSectionSize)
            }
        }
        .confetti(isActive: $showConfetti, duration: confettiDuration)
        .overlay(closeButtonView)
        .colorScheme(.dark)
        .onReceive(productsPub) { _ in
            updateSelectedProduct()
        }
        .onAppear {
            hapticFeedback = HapticFeedback()
            updateSelectedProduct()
            statusTask = Task {
                let statusStream = statusSignal.awaitableStream()
                for await newStatus in statusStream {
                    #if DEBUG
                    print("SGPayWallView: newStatus = \(newStatus)")
                    #endif
                    if Task.isCancelled {
                        #if DEBUG
                        print("statusTask cancelled")
                        #endif
                        break
                    }
                    
                    if currentStatus != newStatus {
                        currentStatus = newStatus

                        if newStatus > 1 {
                            handleUpgradedStatus()
                        }
                    }
                }
            }
        }
        .onDisappear {
            #if DEBUG
            print("Cancelling statusTask")
            #endif
            statusTask?.cancel()
        }
        .onReceive(buyOrRestoreSuccessPub) { _ in
            state = .validating
        }
        .onReceive(buyErrorPub) { notification in
            if let userInfo = notification.userInfo, let error = userInfo["localizedError"] as? String, !error.isEmpty {
                showErrorAlert(error)
            }
        }
        .onReceive(validationErrorPub) { notification in
            if state == .validating {
                if let userInfo = notification.userInfo, let error = userInfo["error"] as? String, !error.isEmpty {
                    showErrorAlert(error.i18n(lang))
                } else {
                    showErrorAlert("PayWall.ValidationError".i18n(lang))
                }
            }
        }
    }
    
    private var featuresSection: some View {
        VStack(spacing: 8) {
            ForEach(features) { feature in
                FeatureRow(
                    icon: feature.icon,
                    title: feature.title,
                    subtitle: feature.subtitle,
                    action: {
                        showDetailsForFeature(feature.id)
                    }
                )
            }
        }
    }
    
    private var restorePurchasesButton: some View {
        Button(action: handleRestorePurchases) {
            Text("PayWall.RestorePurchases".i18n(lang))
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundColor(Color(hex: accentColorHex))
        }
        .disabled(state == .restoring || product == nil)
        .opacity((state == .restoring || product == nil) ? 0.5 : 1.0)
    }
    
    private var purchaseSection: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 8) {
                Button(action: handlePurchase) {
                    Text(buttonTitle)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(hex: accentColorHex))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled((state != .ready || !canPurchase) && !(currentStatus > 1))
                .opacity(((state != .ready || !canPurchase) && !(currentStatus > 1)) ? 0.5 : 1.0)
                
                if let proSupportUrl = proSupportUrl {
                    HStack(alignment: .center, spacing: 4) {
                        Text("PayWall.ProSupport.Title".i18n(lang))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button(action: {
                            openUrl(proSupportUrl, false)
                        }) {
                            Text("PayWall.ProSupport.Contact".i18n(lang))
                                .font(.caption)
                                .foregroundColor(Color(hex: accentColorHex))
                        }
                    }
                }
            }
            .padding([.horizontal, .top])
            .padding(.bottom, sgBottomSafeAreaInset(containerViewLayout) + 2.0)
        }
        .foregroundColor(Color.black)
        .backgroundIfAvailable(material: .ultraThinMaterial)
        .shadow(radius: 8, y: -4)
    }
    
    private var legalSection: some View {
        Group {
            if #available(iOS 15.0, *) {
                Text(LocalizedStringKey("PayWall.Notice.Markdown".i18n(lang, args: "PayWall.TermsURL".i18n(lang), "PayWall.PrivacyURL".i18n(lang))))
                    .font(.caption)
                    .tint(Color(hex: accentColorHex))
                    .foregroundColor(.secondary)
                    .environment(\.openURL, OpenURLAction { url in
                        openUrl(url.absoluteString, false)
                        return .handled
                    })
            } else {
                Text("PayWall.Notice.Raw".i18n(lang))
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(alignment: .top, spacing: 8) {
                    Button(action: {
                        openUrl("PayWall.PrivacyURL".i18n(lang), true)
                    }) {
                        Text("PayWall.Privacy".i18n(lang))
                            .font(.caption)
                            .foregroundColor(Color(hex: accentColorHex))
                    }
                    Button(action: {
                        openUrl("PayWall.TermsURL".i18n(lang), true)
                    }) {
                        Text("PayWall.Terms".i18n(lang))
                            .font(.caption)
                            .foregroundColor(Color(hex: accentColorHex))
                    }
                }
            }
        }
    }
    
    
    private var aboutSection: some View {
        VStack(spacing: 8) {
            HStack {
                Text("PayWall.About.Title".i18n(lang))
                    .font(.headline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            HStack {
                Text("PayWall.About.Notice".i18n(lang))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                Spacer()
            }
            HStack {
                Button(action: {
                    openUrl("PayWall.About.SignatureURL".i18n(lang), false)
                }) {
                    Text("PayWall.About.Signature".i18n(lang))
                        .font(.caption)
                        .foregroundColor(Color(hex: accentColorHex))
                }
                Spacer()
            }
        }
    }
    
    private var closeButtonView: some View {
        Button(action: {
            wrapperController?.dismiss(animated: true)
        }) {
            Image(systemName: "xmark")
                .font(.headline)
                .foregroundColor(.secondary.opacity(0.6))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle()) // Improve tappable area
        }
        .disabled(showDetails)
        .opacity(showDetails ? 0.0 : 1.0)
        .padding([.top, .trailing], 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
        
    private var buttonTitle: String {
        if currentStatus > 1 {
            return "PayWall.Button.OpenPro".i18n(lang)
        } else {
            if state == .purchasing {
                return "PayWall.Button.Purchasing".i18n(lang)
            } else if state == .restoring {
                return "PayWall.Button.Restoring".i18n(lang)
            } else if state == .validating {
                return "PayWall.Button.Validating".i18n(lang)
            } else if let product = product {
                if !SGIAP.canMakePayments || paymentsEnabled == false {
                    return "PayWall.Button.PaymentsUnavailable".i18n(lang)
                } else if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" && !canBuyInBeta {
                    return "PayWall.Button.BuyInAppStore".i18n(lang)
                } else {
                    return "PayWall.Button.Subscribe".i18n(lang, args: product.price)
                }
            } else {
                return "PayWall.Button.ContactingAppStore".i18n(lang)
            }
        }
    }
    
    private var canPurchase: Bool {
        if !SGIAP.canMakePayments || paymentsEnabled == false {
            return false
        } else {
            return product != nil
        }
    }
    
    private func showDetailsForFeature(_ featureId: SGProFeatureId) {
        if #available(iOS 14.0, *) {
            shownFeature = featureId
            showDetails = true
        } // pagination is not available on iOS 13
    }
    
    private func dismissDetails() {
//        shownFeature = nil
        showDetails = false
    }
    
    private func updateSelectedProduct() {
        product = SGIAP.availableProducts.first { $0.id == SG_CONFIG.iaps.first ?? "" }
    }
    
    private func handlePurchase() {
        if currentStatus > 1 {
            wrapperController?.replace(with: replacementController)
        } else {
            if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" && !canBuyInBeta {
                openAppStorePage()
            } else {
                guard let product = product else { return }
                state = .purchasing
                SGIAP.buyProduct(product.skProduct)
            }
        }
    }
    
    private func handleRestorePurchases() {
        state = .restoring
        SGIAP.restorePurchases {
            state = .validating
        }
    }
    
    private func handleUpgradedStatus() {
        DispatchQueue.main.async {
            hapticFeedback?.success()
            showConfetti = true
            DispatchQueue.main.asyncAfter(deadline: .now() + confettiDuration + 1.0) {
                showConfetti = false
            }
        }
    }
    
    private func showErrorAlert(_ message: String) {
        let alertController = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: { action in
            state = .ready
        }))
        DispatchQueue.main.async {
            wrapperController?.present(alertController, animated: true)
        }
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
struct FeatureRow<IconContent: View>: View {
    let icon: IconContent
    let title: String
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
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
                if #available(iOS 14.0, *) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                } // Descriptions are not available on iOS 13
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



// Confetti
@available(iOS 13.0, *)
struct ConfettiType {
    let color: Color
    let shape: ConfettiShape
    
    static func random() -> ConfettiType {
        let colors: [Color] = [.red, .blue, .green, .yellow, .pink, .purple, .orange]
        return ConfettiType(
            color: colors.randomElement() ?? .blue,
            shape: ConfettiShape.allCases.randomElement() ?? .circle
        )
    }
}

@available(iOS 13.0, *)
enum ConfettiShape: CaseIterable {
    case circle
    case triangle
    case square
    case slimRectangle
    case roundedCross
    
    @ViewBuilder
    func view(color: Color) -> some View {
        switch self {
        case .circle:
            Circle().fill(color)
        case .triangle:
            Triangle().fill(color)
        case .square:
            Rectangle().fill(color)
        case .slimRectangle:
            SlimRectangle().fill(color)
        case .roundedCross:
            RoundedCross().fill(color)
        }
    }
}

@available(iOS 13.0, *)
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

@available(iOS 13.0, *)
public struct SlimRectangle: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: 4*rect.maxY/5))
        path.addLine(to: CGPoint(x: rect.maxX, y: 4*rect.maxY/5))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))

        return path
    }
}

@available(iOS 13.0, *)
public struct RoundedCross: Shape {
    public func path(in rect: CGRect) -> Path {
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.maxY/3))
        path.addQuadCurve(to: CGPoint(x: rect.maxX/3, y: rect.minY), control: CGPoint(x: rect.maxX/3, y: rect.maxY/3))
        path.addLine(to: CGPoint(x: 2*rect.maxX/3, y: rect.minY))
        
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY/3), control: CGPoint(x: 2*rect.maxX/3, y: rect.maxY/3))
        path.addLine(to: CGPoint(x: rect.maxX, y: 2*rect.maxY/3))

        path.addQuadCurve(to: CGPoint(x: 2*rect.maxX/3, y: rect.maxY), control: CGPoint(x: 2*rect.maxX/3, y: 2*rect.maxY/3))
        path.addLine(to: CGPoint(x: rect.maxX/3, y: rect.maxY))

        path.addQuadCurve(to: CGPoint(x: 2*rect.minX/3, y: 2*rect.maxY/3), control: CGPoint(x: rect.maxX/3, y: 2*rect.maxY/3))

        return path
    }
}

@available(iOS 13.0, *)
struct ConfettiModifier: ViewModifier {
    @Binding var isActive: Bool
    let duration: Double
    
    func body(content: Content) -> some View {
        content.overlay(
            ZStack {
                if isActive {
                    ForEach(0..<70) { _ in
                        ConfettiPiece(
                            confettiType: .random(),
                            duration: duration
                        )
                    }
                }
            }
        )
    }
}

@available(iOS 13.0, *)
struct ConfettiPiece: View {
    let confettiType: ConfettiType
    let duration: Double
    
    @State private var isAnimating = false
    @State private var rotation = Double.random(in: 0...1080)
    
    var body: some View {
        confettiType.shape.view(color: confettiType.color)
            .frame(width: 10, height: 10)
            .rotationEffect(.degrees(rotation))
            .position(
                x: .random(in: 0...UIScreen.main.bounds.width),
                y: 0 //-20
            )
            .modifier(FallingModifier(distance: UIScreen.main.bounds.height + 20, duration: duration))
            .opacity(isAnimating ? 0 : 1)
            .onAppear {
                withAnimation(.linear(duration: duration)) {
                    isAnimating = true
                }
            }
    }
}

@available(iOS 13.0, *)
struct FallingModifier: ViewModifier {
    let distance: CGFloat
    let duration: Double
    
    func body(content: Content) -> some View {
        content.modifier(
            MoveModifier(
                offset: CGSize(
                    width: .random(in: -100...100),
                    height: distance
                ),
                duration: duration
            )
        )
    }
}

@available(iOS 13.0, *)
struct MoveModifier: ViewModifier {
    let offset: CGSize
    let duration: Double
    
    @State private var isAnimating = false
    
    func body(content: Content) -> some View {
        content.offset(
            x: isAnimating ? offset.width : 0,
            y: isAnimating ? offset.height : 0
        )
        .onAppear {
            withAnimation(
                .linear(duration: duration)
                .speed(.random(in: 0.5...2.5))
            ) {
                isAnimating = true
            }
        }
    }
}

// Extension to make it easier to use
@available(iOS 13.0, *)
extension View {
    func confetti(isActive: Binding<Bool>, duration: Double = 2.0) -> some View {
        modifier(ConfettiModifier(isActive: isActive, duration: duration))
    }
}
