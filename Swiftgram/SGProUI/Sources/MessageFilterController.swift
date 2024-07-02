import Foundation
import SwiftUI
import SGSwiftUI
import SGStrings
import SGSimpleSettings
import LegacyUI
import Display
import TelegramPresentationData

@available(iOS 13.0, *)
struct MessageFilterKeywordInputFieldModifier: ViewModifier {
    @Binding var newKeyword: String
    let onAdd: () -> Void
    
    func body(content: Content) -> some View {
        if #available(iOS 15.0, *) {
            content
                .submitLabel(.return)
                .submitScope(false) // TODO(swiftgram): Keyboard still closing
                .interactiveDismissDisabled()
                .onSubmit {
                    onAdd()
                }
        } else {
            content
        }
    }
}


@available(iOS 13.0, *)
struct MessageFilterKeywordInputView: View {
    @Environment(\.lang) var lang: String
    @Binding var newKeyword: String
    let onAdd: () -> Void

    var body: some View {
        HStack {
            TextField("MessageFilter.InputPlaceholder".i18n(lang), text: $newKeyword)
                .autocorrectionDisabled(true)
                .autocapitalization(.none)
                .keyboardType(.default)
                .modifier(MessageFilterKeywordInputFieldModifier(newKeyword: $newKeyword, onAdd: onAdd))
                
            
            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : .accentColor)
                    .imageScale(.large)
            }
            .disabled(newKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .buttonStyle(PlainButtonStyle())
        }
    }
}

@available(iOS 13.0, *)
struct MessageFilterView: View {
    weak var wrapperController: LegacyController?
    @Environment(\.lang) var lang: String
    
    @State private var newKeyword: String = ""
    @State private var keywords: [String] {
        didSet {
            SGSimpleSettings.shared.messageFilterKeywords = keywords
        }
    }
    
    init(wrapperController: LegacyController?) {
        self.wrapperController = wrapperController
        _keywords = State(initialValue: SGSimpleSettings.shared.messageFilterKeywords)
    }
    
    var bodyContent: some View {
            List {
                Section {
                    // Icon and title
                    VStack(spacing: 8) {
                        Image(systemName: "nosign.app.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.secondary)
                        
                        Text("MessageFilter.Title".i18n(lang))
                            .font(.title)
                            .bold()
                        
                        Text("MessageFilter.SubTitle".i18n(lang))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .listRowInsets(EdgeInsets())
                    
                }
                
                Section {
                    MessageFilterKeywordInputView(newKeyword: $newKeyword, onAdd: addKeyword)
                }
                
                Section(header: Text("MessageFilter.Keywords.Title".i18n(lang))) {
                    ForEach(keywords.reversed(), id: \.self) { keyword in
                        Text(keyword)
                    }
                    .onDelete { indexSet in
                        let originalIndices = IndexSet(
                            indexSet.map { keywords.count - 1 - $0 }
                        )
                        deleteKeywords(at: originalIndices)
                    }
                }
        }
        .tgNavigationBackButton(wrapperController: wrapperController)
    }
    
    var body: some View {
        NavigationView {
            if #available(iOS 14.0, *) {
                bodyContent
                    .toolbar {
                        EditButton()
                    }
            } else {
                bodyContent
            }
        }
    }
    
    private func addKeyword() {
        let trimmedKeyword = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKeyword.isEmpty else { return }
        
        let keywordExists = keywords.contains {
            $0 == trimmedKeyword
        }
        
        guard !keywordExists else {
            return
        }
        
        withAnimation {
            keywords.append(trimmedKeyword)
        }
        newKeyword = ""
        
    }
    
    private func deleteKeywords(at offsets: IndexSet) {
        withAnimation {
            keywords.remove(atOffsets: offsets)
        }
    }
}

@available(iOS 13.0, *)
public func sgMessageFilterController(presentationData: PresentationData? = nil) -> ViewController {
    let theme = presentationData?.theme ?? (UITraitCollection.current.userInterfaceStyle == .dark ? defaultDarkColorPresentationTheme : defaultPresentationTheme)
    let strings = presentationData?.strings ?? defaultPresentationStrings

    let legacyController = LegacySwiftUIController(
        presentation: .navigation,
        theme: theme,
        strings: strings
    )
    // Status bar color will break if theme changed
    legacyController.statusBar.statusBarStyle = theme.rootController
        .statusBarStyle.style
    legacyController.displayNavigationBar = false
    let swiftUIView = SGSwiftUIView<MessageFilterView>(
        legacyController: legacyController,
        content: {
            MessageFilterView(wrapperController: legacyController)
        }
    )
    let controller = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
    legacyController.bind(controller: controller)

    return legacyController
}
