import AsyncDisplayKit
import Display
import Foundation
import SGSwiftUI
import SwiftSignalKit
import SwiftUI
import TelegramPresentationData
import UIKit

/// Shared signal exercises Telegram theme updates without an account or network connection.
final class PlaygroundPresentation {
    static let shared = PlaygroundPresentation()
    private(set) var data = defaultPresentationData()
    let changes = ValuePromise<PresentationData>(defaultPresentationData(), ignoreRepeated: true)
    weak var navigationController: NavigationController?
    private var usesPurpleAccent = false

    func toggleTheme() {
        self.updateTheme(dark: !self.data.theme.overallDarkAppearance)
    }

    func toggleAccent() {
        self.usesPurpleAccent.toggle()
        self.updateTheme(dark: self.data.theme.overallDarkAppearance)
    }

    private func updateTheme(dark: Bool) {
        let base = dark ? defaultDarkPresentationTheme : defaultPresentationTheme
        let theme = self.usesPurpleAccent ? customizePresentationTheme(base, editing: false, accentColor: UIColor(rgb: 0xAF52DE), outgoingAccentColor: nil, backgroundColors: [], bubbleColors: [], animateBubbleColors: false) : base
        self.data = self.data.withUpdated(theme: theme)
        self.changes.set(self.data)
        self.navigationController?.updateTheme(NavigationControllerTheme(statusBar: theme.overallDarkAppearance ? .white : .black, navigationBar: NavigationBarTheme(rootControllerTheme: theme), emptyAreaColor: theme.list.blocksBackgroundColor, separatorColor: theme.rootController.navigationBar.separatorColor, opaqueBackgroundColor: theme.list.blocksBackgroundColor))
    }
}

func playgroundScreen<Content: View>(_ title: String, showsNavigationBar: Bool = true, ownsNavigation: Bool = true, @ViewBuilder content: () -> Content) -> SGSwiftUIController<Content> {
    let presentation = PlaygroundPresentation.shared
    return SGSwiftUIController(title: title, presentationData: presentation.data, presentationDataSignal: presentation.changes.get(), showsNavigationBar: showsNavigationBar, ownsNavigation: ownsNavigation, content: content)
}

func playgroundRootController() -> ViewController {
    return playgroundScreen("SwiftUI Playground") { PlaygroundMenu() }
}

func playgroundNativeReferenceController() -> UIViewController {
    return UIHostingController(rootView: NavigationView { PlaygroundMenu().navigationTitle("Native reference") }.navigationViewStyle(.stack))
}

private struct PlaygroundMenu: View {
    @Environment(\.sgNavigation) private var navigation
    @State private var showsSheet = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SwiftUI × Telegram").font(.title2.bold())
                    Text("One stack. Native safe areas. No screen-specific padding.")
                        .font(.subheadline).foregroundColor(.secondary)
                }.padding(.vertical, 8)
            }
            Section(header: Text("Navigation")) {
                Button("Push SwiftUI screen") {
                    navigation?.push(title: "SwiftUI child") { PlaygroundGeometry(name: "SwiftUI child") }
                }.accessibilityIdentifier("push-swiftui")
                Button("Push Telegram controller") {
                    navigation?.push(PlaygroundTelegramController())
                }.accessibilityIdentifier("push-telegram")
                Button("Present Telegram modal") {
                    navigation?.present(title: "Telegram modal") { PlaygroundGeometry(name: "Telegram modal") }
                }.accessibilityIdentifier("modal-telegram")
                Button("Isolated native SwiftUI flow") {
                    navigation?.push(playgroundScreen("Native flow", showsNavigationBar: false, ownsNavigation: false) { PlaygroundNativeFlow() })
                }.accessibilityIdentifier("native-flow")
            }
            Section(header: Text("Standard screens")) {
                Button("List / Form / keyboard") {
                    navigation?.push(title: "Form & keyboard") { PlaygroundForm() }
                }.accessibilityIdentifier("show-form")
                Button("Safe-area colors & scrolling") {
                    navigation?.push(title: "Safe-area geometry") { PlaygroundGeometry(name: "Safe-area geometry") }
                }.accessibilityIdentifier("show-geometry")
                Button("Present native SwiftUI sheet") { showsSheet = true }
                    .accessibilityIdentifier("swiftui-sheet")
                Button("Live theme & accent") {
                    navigation?.push(title: "SwiftUI theme") {
                        PlaygroundThemeScreen(toggleAccent: { PlaygroundPresentation.shared.toggleAccent() }, toggleAppearance: { PlaygroundPresentation.shared.toggleTheme() })
                    }
                }.accessibilityIdentifier("show-theme")
                Button("Toggle Telegram theme") { PlaygroundPresentation.shared.toggleTheme() }
                    .accessibilityIdentifier("toggle-theme")
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showsSheet) { PlaygroundSheet() }
        .accessibilityIdentifier("playground-menu")
    }
}

private struct PlaygroundGeometry: View {
    let name: String
    @Environment(\.sgNavigation) private var navigation
    @Environment(\.containerViewLayout) private var layout
    @Environment(\.navigationBarHeight) private var navigationHeight
    @Environment(\.sgIsVisible) private var isVisible
    @State private var count = 0
    @State private var appearances = 0
    @State private var disappearances = 0

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 16) {
                    Text("TOP · safe content begins here")
                        .font(.headline).frame(maxWidth: .infinity).padding()
                        .background(Color.green.opacity(0.8))
                        .accessibilityIdentifier("safe-top")
                    VStack(alignment: .leading, spacing: 8) {
                        Text(name).font(.title2.bold()).accessibilityIdentifier("geometry-name")
                        Text("Green: content boundary\nBlue: full-bleed background\nOrange: safeAreaInset bottom action")
                        Text("Container \(Int(layout?.size.width ?? 0)) × \(Int(layout?.size.height ?? 0)) · nav \(Int(navigationHeight))\nSafe T\(Int(geometry.safeAreaInsets.top)) B\(Int(geometry.safeAreaInsets.bottom)) L\(Int(geometry.safeAreaInsets.leading)) R\(Int(geometry.safeAreaInsets.trailing))\nVisible \(isVisible ? "yes" : "no") · appearances \(appearances) · disappearances \(disappearances) · state \(count)")
                            .font(.system(.caption, design: .monospaced))
                            .accessibilityIdentifier("layout-diagnostics")
                            .accessibilityValue(Text(verbatim: "container=\(layout?.size.width ?? 0),\(layout?.size.height ?? 0);size=\(geometry.size.width),\(geometry.size.height);safe=\(geometry.safeAreaInsets.top),\(geometry.safeAreaInsets.leading),\(geometry.safeAreaInsets.bottom),\(geometry.safeAreaInsets.trailing);nav=\(navigationHeight);formSheet=\(layout?.presentedInFormSheet == true)"))
                        Button("Increment state: \(count)") { count += 1 }
                            .accessibilityIdentifier("increment-state")
                        Button("Toggle theme in place") { PlaygroundPresentation.shared.toggleTheme() }
                            .accessibilityIdentifier("geometry-toggle-theme")
                        Button("Push SwiftUI child") {
                            navigation?.push(title: "Another SwiftUI child") { PlaygroundGeometry(name: "Another SwiftUI child") }
                        }.accessibilityIdentifier("geometry-push-swiftui")
                        Button("Push Telegram from SwiftUI") { navigation?.push(PlaygroundTelegramController()) }
                            .accessibilityIdentifier("geometry-push-telegram")
                        Button("Present another Telegram modal") {
                            navigation?.present(title: "Nested modal") { PlaygroundGeometry(name: "Nested modal") }
                        }.accessibilityIdentifier("geometry-modal")
                        Button("Close this screen") { navigation?.dismiss() }
                            .accessibilityIdentifier("close-screen")
                    }
                    .padding().frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    ForEach(1...12, id: \.self) { index in
                        Text("Standard ScrollView row \(index)")
                            .frame(maxWidth: .infinity, alignment: .leading).padding()
                            .background(Color(uiColor: .secondarySystemBackground)).cornerRadius(8)
                            .padding(.horizontal)
                    }
                    Text("LAST ROW · scrolls above bottom action")
                        .font(.headline).padding().accessibilityIdentifier("last-row")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button("BOTTOM ACTION · state \(count)") { count += 1 }
                    .font(.headline).frame(maxWidth: .infinity).padding()
                    .background(Color.orange).foregroundColor(.black)
                    .accessibilityIdentifier("bottom-action")
            }
            .background(Color.blue.opacity(0.2).ignoresSafeArea())
        }
        .onAppear { appearances += 1 }
        .onDisappear { disappearances += 1 }
    }
}

private struct PlaygroundForm: View {
    @Environment(\.sgNavigation) private var navigation
    @State private var text = ""
    @State private var enabled = true
    @State private var choice = 0
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section(header: Text("Native SwiftUI Form"), footer: Text("Keyboard avoidance belongs to SwiftUI. The adapter never adds inputHeight padding.")) {
                TextField("Type to test the keyboard", text: $text)
                    .focused($focused).accessibilityIdentifier("keyboard-field")
                Toggle("Standard toggle", isOn: $enabled)
                Picker("Selection", selection: $choice) {
                    Text("First").tag(0)
                    Text("Second").tag(1)
                }.pickerStyle(.segmented)
                Button("Dismiss keyboard") { focused = false }.accessibilityIdentifier("hide-keyboard")
            }
            Section {
                Button("Push while keyboard visible") {
                    navigation?.push(title: "Keyboard destination") { PlaygroundGeometry(name: "Keyboard destination") }
                }.accessibilityIdentifier("keyboard-push")
            }
            Section(header: Text("Scroll & focus")) {
                ForEach(0..<14) { index in Text("Form row \(index)") }
                TextField("Bottom text field", text: $text).accessibilityIdentifier("bottom-field")
            }
        }
        .onChange(of: focused) { value in
            if value {
                // FocusState publishes before UIKit has installed the new first responder.
                DispatchQueue.main.async {
                    if focused { playgroundEnsureSoftwareKeyboard() }
                }
            }
        }
        .onChange(of: text) { _ in
            if focused {
                DispatchQueue.main.async {
                    if focused { playgroundEnsureSoftwareKeyboard() }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Text("FORM BOTTOM · above keyboard / home indicator")
                .font(.caption.bold()).frame(maxWidth: .infinity).padding()
                .background(Color.orange).foregroundColor(.black)
                .accessibilityIdentifier("form-bottom")
        }
    }
}

private struct PlaygroundSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationView {
            Form {
                Text("Native sheet · native dismiss").font(.headline)
                TextField("Sheet text field", text: $text).focused($focused)
                Text("This sheet must not inherit Telegram's navigation-bar padding.")
                Button("Dismiss without toolbar") {
                    dismiss()
                }.accessibilityIdentifier("sheet-content-done")
            }
            .navigationTitle("SwiftUI sheet")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("sheet-done")
                }
            }
        }.navigationViewStyle(.stack)
        .onChange(of: focused) { value in
            if value {
                // FocusState publishes before UIKit has installed the new first responder.
                DispatchQueue.main.async {
                    if focused { playgroundEnsureSoftwareKeyboard() }
                }
            }
        }
        .onChange(of: text) { _ in
            if focused {
                DispatchQueue.main.async {
                    if focused { playgroundEnsureSoftwareKeyboard() }
                }
            }
        }
    }
}

private struct PlaygroundNativeFlow: View {
    @Environment(\.sgNavigation) private var navigation

    var body: some View {
        NavigationView {
            List {
                Text("Native inner navigation owns Back; Telegram's ancestor swipe is disabled.")
                NavigationLink("Open inner SwiftUI child") { PlaygroundNativeChild() }
                    .accessibilityIdentifier("inner-link")
            }
            .navigationTitle("Inner root")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close flow") { navigation?.dismiss() }.accessibilityIdentifier("close-flow")
                }
            }
        }.navigationViewStyle(.stack)
    }
}

private struct PlaygroundNativeChild: View {
    @Environment(\.sgNavigation) private var navigation
    var body: some View {
        List {
            Text("Native child · Back returns to Inner root")
                .accessibilityIdentifier("inner-child")
            Button("Push Telegram over inner flow") { navigation?.push(PlaygroundTelegramController()) }
                .accessibilityIdentifier("inner-push-telegram")
        }.navigationTitle("Inner child")
    }
}

/// Deliberately NOT SwiftUI: a plain Telegram Display.ViewController with UIKit content.
final class PlaygroundTelegramController: ViewController {
    private let contentView = UIStackView()
    private let marker = UILabel()

    init() {
        let data = PlaygroundPresentation.shared.data
        super.init(navigationBarPresentationData: NavigationBarPresentationData(theme: NavigationBarTheme(rootControllerTheme: data.theme), strings: NavigationBarStrings(presentationStrings: data.strings)))
        self.title = "Telegram controller"
        self.statusBar.statusBarStyle = data.theme.rootController.statusBarStyle.style
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadDisplayNode() {
        self.displayNode = ViewControllerTracingNode()
        self.displayNode.backgroundColor = UIColor.systemTeal
        self.displayNodeDidLoad()
        self.contentView.axis = .vertical
        self.contentView.spacing = 20
        self.marker.text = "Telegram / UIKit screen"
        self.marker.font = .preferredFont(forTextStyle: .title2)
        self.marker.adjustsFontForContentSizeCategory = true
        self.marker.numberOfLines = 0
        self.marker.accessibilityIdentifier = "telegram-screen"
        self.contentView.addArrangedSubview(self.marker)
        let details = UILabel()
        details.text = "SwiftUI → Telegram → SwiftUI\nBack must remove one screen only."
        details.numberOfLines = 0
        self.contentView.addArrangedSubview(details)
        let button = UIButton(type: .system)
        button.setTitle("Push SwiftUI from Telegram", for: .normal)
        button.accessibilityIdentifier = "telegram-push-swiftui"
        button.addAction(UIAction { [weak self] _ in
            self?.push(playgroundScreen("SwiftUI from Telegram") { PlaygroundGeometry(name: "SwiftUI from Telegram") })
        }, for: .touchUpInside)
        self.contentView.addArrangedSubview(button)
        self.displayNode.view.addSubview(self.contentView)
    }

    override func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let insets = layout.insets(options: .statusBar)
        let top = max(insets.top, self.navigationLayout(layout: layout).navigationFrame.maxY)
        let side: CGFloat = 20
        self.contentView.frame = CGRect(x: layout.safeInsets.left + side, y: top + side, width: layout.size.width - layout.safeInsets.left - layout.safeInsets.right - 2 * side, height: self.contentView.systemLayoutSizeFitting(CGSize(width: layout.size.width - 2 * side, height: 0)).height)
    }
}
