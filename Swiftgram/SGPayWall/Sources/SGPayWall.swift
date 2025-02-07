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

//
//import SwiftUI
//
//
//struct ModalView: View {
//    @State private var isShowingModal = true
//    
//    var body: some View {
//        Button("Show Modal") {
//            isShowingModal.toggle()
//        }
//        .sheet(isPresented: $isShowingModal) {
//            ContentView()
//                .presentationDetents([.large]) // iOS 16+
//                .presentationDragIndicator(.hidden)
//        }
//    }
//}
//
//let innerShadowWidth: CGFloat = 15.0
//
//struct BackgroundView: View {
//    var body: some View {
//        ZStack {
//            LinearGradient(
//                gradient: Gradient(stops: [
//                    .init(color: Color(hex: "A053F8").opacity(0.8), location: 0.0),
//                    .init(color: Color.clear, location: 0.20),
//                    
//                ]),
//                startPoint: .topLeading,
//                endPoint: .bottomTrailing
//            )
//            .edgesIgnoringSafeArea(.all)
//            LinearGradient(
//                gradient: Gradient(stops: [
//                    .init(color: Color(hex: "CC4303").opacity(0.6), location: 0.0),
//                    .init(color: Color.clear, location: 0.15),
//                ]),
//                startPoint: .topTrailing,
//                endPoint: .bottomLeading
//            )
//            .blendMode(.lighten)
//            
//            .edgesIgnoringSafeArea(.all)
//            .overlay(
//                RoundedRectangle(cornerRadius: 0)
//                    .stroke(Color.clear, lineWidth: 0)
//                    .background(
//                        ZStack {
//                            innerShadow(x: -2, y: -2, blur: 4, color: Color(hex: "FF8C56")) // orange shadow
//                            innerShadow(x: 2, y: 2, blur: 4, color: Color(hex: "A053F8")) // purple shadow
//                            //                                innerShadow(x: 0, y: 0, blur: 4, color: Color.white.opacity(0.3))
//                        }
//                    )
//            ).ignoresSafeArea(.all)
//        }
//        .background(Color.black)
//    }
//    
//    func innerShadow(x: CGFloat, y: CGFloat, blur: CGFloat, color: Color) -> some View {
//        return RoundedRectangle(cornerRadius: 0)
//            .stroke(color, lineWidth: innerShadowWidth)
//            .blur(radius: blur)
//            .offset(x: x, y: y)
//            .mask(RoundedRectangle(cornerRadius: 0).fill(LinearGradient(gradient: Gradient(colors: [Color.black, Color.clear]), startPoint: .top, endPoint: .bottom)))
//    }
//}
//
//extension Color {
//    init(hex: String) {
//        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
//        var int: UInt64 = 0
//        Scanner(string: hex).scanHexInt64(&int)
//        let a, r, g, b: UInt64
//        switch hex.count {
//        case 6: // RGB (No alpha)
//            (a, r, g, b) = (255, (int >> 16) & 0xff, (int >> 8) & 0xff, int & 0xff)
//        case 8: // ARGB
//            (a, r, g, b) = ((int >> 24) & 0xff, (int >> 16) & 0xff, (int >> 8) & 0xff, int & 0xff)
//        default:
//            (a, r, g, b) = (255, 0, 0, 0)
//        }
//        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
//    }
//}
//
//
//
//struct ContentView: View {
//    var body: some View {
//        bodyContent
//            .overlay(closeButtonView
//                .padding([.top, .trailing], 16) // Add padding from top and right edges
//                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
//            )
//    }
//    
//    var bodyContent: some View {
//        ZStack {
//            BackgroundView()
//            ZStack(alignment: .bottom) {
//                ScrollView(showsIndicators: false) {
//                    VStack(spacing: 24) {
//                        // Premium Icon
//                        PremiumIconView()
//                            .frame(width: 100, height: 100)
//                        
//                        // Title and Subtitle
//                        VStack(spacing: 8) {
//                            Text("Swiftgram Pro")
//                                .font(.largeTitle)
//                                .fontWeight(.bold)
//                            
//                            Text("Supercharged with Pro features")
//                                .font(.callout)
//                            //                            .foregroundColor(.secondary)
//                                .multilineTextAlignment(.center)
//                                .padding(.horizontal)
//                        }
//                        
//                        // Features List
//                        VStack(spacing: 8) {
//                            FeatureRow(
//                                icon: FeatureIcon(icon: "lock.fill", backgroundColor: .blue),
//                                title: "Session Backup",
//                                subtitle: "Restore sessions from encrypted local Apple Keychain backup."
//                            )
//                            
//                            FeatureRow(
//                                icon: FeatureIcon(icon: "nosign", backgroundColor: .gray, fontWeight: .bold),
//                                title: "Message Filter",
//                                subtitle: "Reduce visibility of spam, promotions and annoying messages."
//                            )
//                            
//                            FeatureRow(
//                                icon: FeatureIcon(icon: "bell.badge.slash.fill", backgroundColor: .red),
//                                title: "Disable @mentions and replies",
//                                subtitle: "Hide or silence non-important notifications."
//                            )
//                            
//                            FeatureRow(
//                                icon: FeatureIcon(icon: "bold.underline", backgroundColor: .blue, iconSize: 16),
//                                title: "Quick Formatting panel",
//                                subtitle: "Save time preparing your posts with a panel right above your keyboard."
//                            )
//                            
//                            
//                        }
//                        .padding(.horizontal, innerShadowWidth + 8.0)
//                        
//                        Text("Privacy Policy")
//                            .font(.footnote)
//                        
//                        Color.clear.frame(height: 40)
//                    }
//                    .padding(.vertical, 40)
//                }
//                // Fixed purchase button at bottom
//                VStack(spacing: 0) {
//                    Divider()
//                    
//                    Button(action: {
//                        // Your purchase action here
//                    }) {
//                        Text("Subscribe for $9.99 / month")
//                            .fontWeight(.semibold)
//                            .frame(maxWidth: .infinity)
//                            .padding()
//                            .background(Color(hex: "F1552E"))
//                            .foregroundColor(.white)
//                            .cornerRadius(12)
//                    }
//                    .padding()
//                }
//                .foregroundColor(Color.black)
//                .background(.ultraThinMaterial)
//                .shadow(radius: 8, y: -4)
//            }
//        }
//        .colorScheme(.dark)
//    }
//    
//    private var closeButtonView: some View {
//        Button(action: {
//            
//        }) {
//            Image(systemName: "xmark")
//                .font(.headline)
//                .foregroundColor(.secondary.opacity(0.6))
//        }
//    }
//}
//
//// Premium Icon View using SVG
//struct PremiumIconView: View {
//    var body: some View {
//        Image("PRO") // You'll need to add the SVG to your assets
//    }
//}
//
//struct FeatureIcon: View {
//    let icon: String
//    let iconColor: Color
//    let backgroundColor: Color
//    let iconSize: CGFloat
//    let frameSize: CGFloat
//    let fontWeight: Font.Weight
//    
//    init(
//        icon: String,
//        iconColor: Color = .white,
//        backgroundColor: Color = .blue,
//        iconSize: CGFloat = 18,
//        frameSize: CGFloat = 32,
//        fontWeight: Font.Weight = .regular
//    ) {
//        self.icon = icon
//        self.iconColor = iconColor
//        self.backgroundColor = backgroundColor
//        self.iconSize = iconSize
//        self.frameSize = frameSize
//        self.fontWeight = fontWeight
//    }
//    
//    var body: some View {
//        Image(systemName: icon)
//            .font(.system(size: iconSize))
//            .fontWeight(fontWeight)
//            .foregroundColor(iconColor)
//            .frame(width: frameSize, height: frameSize)
//            .background(backgroundColor)
//            .clipShape(RoundedRectangle(cornerRadius: 8))
//    }
//}
//
//
//// Feature Row Component
//struct FeatureRow: View {
//    let icon: FeatureIcon
//    let title: String
//    let subtitle: String
//    
//    var body: some View {
//        Button(action: {
//            // Add your tap action here
//        }) {
//            HStack(spacing: 16) {
//                
//                HStack(alignment: .top, spacing: 12) {
//                    icon
//                    
//                    VStack(alignment: .leading, spacing: 4) {
//                        Text(title)
//                            .font(.headline)
//                            .fontWeight(.medium)
//                        
//                        Text(subtitle)
//                            .font(.subheadline)
//                            .foregroundColor(.secondary)
//                    }
//                }
//                
//                Spacer()
//                
//                Image(systemName: "chevron.right")
//                    .font(.system(size: 12, weight: .semibold))
//                    .foregroundColor(.secondary)
//            }
//            .padding()
//            .background(
//                RoundedRectangle(cornerRadius: 12)
//                    .fill(Color(.systemGray6))
//                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
//            )
//        }
//        .buttonStyle(PlainButtonStyle())
//    }
//}
//
//
//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ModalView()
//    }
//}
