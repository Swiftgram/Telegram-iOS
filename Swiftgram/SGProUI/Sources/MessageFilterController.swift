import Foundation
import SwiftUI
import UIKit
import SGSwiftUI
import SGStrings
import SGSimpleSettings
import AccountContext
import Display
import TelegramPresentationData

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
                .submitLabel(.return)
                .submitScope(false) // TODO(swiftgram): Keyboard still closing
                .interactiveDismissDisabled()
                .onSubmit {
                    onAdd()
                }
                
            
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

private final class MessageFilterEditing: NSObject, ObservableObject {
    @Published var editMode: EditMode = .inactive
    weak var controller: ViewController?
    var strings: PresentationStrings = defaultPresentationStrings

    func updateBarButton() {
        controller?.navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: editMode.isEditing ? strings.Common_Done : strings.Common_Edit,
            style: editMode.isEditing ? .done : .plain,
            target: self,
            action: #selector(toggleEditing)
        )
    }

    @objc private func toggleEditing() {
        withAnimation {
            editMode = editMode.isEditing ? .inactive : .active
        }
        updateBarButton()
    }
}

struct MessageFilterView: View {
    @Environment(\.lang) var lang: String
    @ObservedObject fileprivate var editing: MessageFilterEditing
    let context: AccountContext
    
    @State private var newKeyword: String = ""
    @State private var keywords: [String] {
        didSet {
            SGSimpleSettings.shared.messageFilterKeywords = keywords
        }
    }
    
    fileprivate init(editing: MessageFilterEditing, context: AccountContext) {
        self.editing = editing
        self.context = context
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
    }
    
    var body: some View {
        bodyContent
            .environment(\.editMode, $editing.editMode)
            .sgNavigationTitle("MessageFilter.Title".i18n(lang))
            .onAppear(perform: updateBarButton)
            .onChange(of: lang) { _ in updateBarButton() }
    }

    private func updateBarButton() {
        editing.strings = context.sharedContext.currentPresentationData.with { $0 }.strings
        editing.updateBarButton()
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

public func sgMessageFilterController(context: AccountContext, presentationData: PresentationData? = nil) -> ViewController {
    let presentationData = presentationData ?? context.sharedContext.currentPresentationData.with { $0 }
    let editing = MessageFilterEditing()
    let controller = SGSwiftUIController(
        title: "MessageFilter.Title".i18n(presentationData.strings.baseLanguageCode),
        presentationData: presentationData,
        presentationDataSignal: context.sharedContext.presentationData
    ) {
        MessageFilterView(editing: editing, context: context)
    }
    editing.controller = controller
    editing.strings = presentationData.strings
    editing.updateBarButton()
    return controller
}
