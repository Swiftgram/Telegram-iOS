import Foundation
import UniformTypeIdentifiers
import SGItemListUI
import UndoUI
import AccountContext
import Display
import TelegramCore
import Postbox
import ItemListUI
import SwiftSignalKit
import TelegramPresentationData
import PresentationDataUtils

// Optional
import SGSimpleSettings
import SGLogging
import OverlayStatusController
#if DEBUG
import FLEX
#endif
import Security


let BACKUP_SERVICE: String = "\(Bundle.main.bundleIdentifier!).sessionsbackup"

enum KeychainError: Error {
    case duplicateEntry
    case unknown(OSStatus)
    case itemNotFound
    case invalidItemFormat
}

class KeychainBackupManager {
    static let shared = KeychainBackupManager()
    private let service = "\(Bundle.main.bundleIdentifier!).sessionsbackup"
    
    private init() {}
    
    // MARK: - Save Credentials
    func saveSession(id: String, _ session: Data) throws {
        // Create query dictionary
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecValueData as String: session,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        // Add to keychain
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecDuplicateItem {
            // Item already exists, update it
            let updateQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: id
            ]
            
            let attributesToUpdate: [String: Any] = [
                kSecValueData as String: session
            ]
            
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary,
                                          attributesToUpdate as CFDictionary)
            
            if updateStatus != errSecSuccess {
                throw KeychainError.unknown(updateStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unknown(status)
        }
    }
    
    // MARK: - Retrieve Credentials
    func retrieveSession(for id: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let sessionData = result as? Data else {
            throw KeychainError.itemNotFound
        }
        
        return sessionData
    }
    
    // MARK: - Delete Credentials
    func deleteSession(for id: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unknown(status)
        }
    }
    
    // MARK: - Retrieve All Accounts
    func getAllSessons() throws -> [Data] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return []
        }
        
        guard status == errSecSuccess,
              let credentialsDataArray = result as? [Data] else {
            throw KeychainError.unknown(status)
        }
        
        return credentialsDataArray
    }
    
    // MARK: - Delete All Sessions
    func deleteAllSessions() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        // If no items were found, that's fine - just return
        if status == errSecItemNotFound {
            return
        }
        
        // For any other error, throw
        if status != errSecSuccess {
            throw KeychainError.unknown(status)
        }
    }
}

struct SessionBackup: Codable {
    var name: String? = nil
    var date: Date = Date()
    let accountRecord: AccountRecord<TelegramAccountManagerTypes.Attribute>
    
    var peerIdInternal: Int64 {
        var userId: Int64 = 0
        for attribute in accountRecord.attributes {
            if case let .backupData(backupData) = attribute, let backupPeerID = backupData.data?.peerId {
                userId = backupPeerID
                break
            }
        }
        return userId
    }
    
    var userId: Int64 {
        return PeerId(peerIdInternal).id._internalGetInt64Value()
    }
}

import SwiftUI
import SGSwiftUI
import LegacyUI
import SGStrings


@available(iOS 13.0, *)
struct SessionBackupRow: View {
    let backup: SessionBackup
    let isLoggedIn: Bool
    
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    var formattedDate: String {
        if #available(iOS 15.0, *) {
            return backup.date.formatted(date: .abbreviated, time: .shortened)
        } else {
            return dateFormatter.string(from: backup.date)
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(backup.name ?? String(backup.userId))
                    .font(.body)
                
                Text("ID: \(backup.userId)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Last Backup: \(formattedDate)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(isLoggedIn ? "Logged In" : "Logged Out")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.vertical, 4)
    }
}


@available(iOS 13.0, *)
struct BorderedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.accentColor, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

@available(iOS 13.0, *)
struct SessionBackupManagerView: View {
    weak var wrapperController: LegacyController?
    let context: AccountContext
    
    @State private var sessions: [SessionBackup] = []
    @State private var loggedInPeerIDs: [Int64] = []
    @State private var loggedInAccountsDisposable: Disposable? = nil
    
    private func performBackup() {
        let controller = OverlayStatusController(theme: context.sharedContext.currentPresentationData.with { $0 }.theme, type: .loading(cancelled: nil))
        
        let signal = context.sharedContext.accountManager.accountRecords()
        |> take(1)
        |> deliverOnMainQueue
        
        let signal2 = context.sharedContext.activeAccountsWithInfo
        |> take(1)
        |> deliverOnMainQueue
        
        wrapperController?.present(controller, in: .window(.root), with: nil)
        
        Task {
            let (view, accountsWithInfo) = await combineLatest(signal, signal2).awaitable()
            backupSessionsFromView(view, accountsWithInfo: accountsWithInfo.1)
            withAnimation {
                sessions = getBackedSessions()
            }
            controller.dismiss()
        }
        
    }
    
    private func performRestore() {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let controller = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
        
        let _ = (context.sharedContext.accountManager.accountRecords()
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak controller] view in
            
            let backupSessions = getBackedSessions()
            var restoredSessions: Int64 = 0
            
            func importNextBackup(index: Int) {
                // Check if we're done
                if index >= backupSessions.count {
                    // All done, update UI
                    withAnimation {
                        sessions = getBackedSessions()
                    }
                    controller?.dismiss()
                    wrapperController?.present(
                        okUndoController("OK: \(restoredSessions) Sessions restored", presentationData),
                        in: .current
                    )
                    return
                }
                
                let backup = backupSessions[index]
                
                // Check for existing record
                let existingRecord = view.records.first { record in
                    var userId: Int64 = 0
                    for attribute in record.attributes {
                        if case let .backupData(backupData) = attribute {
                            userId = backupData.data?.peerId ?? 0
                        }
                    }
                    return userId == backup.peerIdInternal
                }
                
                if existingRecord != nil {
                    print("Record \(backup.userId) already exists, skipping")
                    importNextBackup(index: index + 1)
                    return
                }
                
                var importAttributes = backup.accountRecord.attributes
                importAttributes.removeAll { attribute in
                    if case .sortOrder = attribute {
                        return true
                    }
                    return false
                }
                
                let importBackupSignal = context.sharedContext.accountManager.transaction { transaction -> Void in
                    let nextSortOrder = (transaction.getRecords().map({ record -> Int32 in
                        for attribute in record.attributes {
                            if case let .sortOrder(sortOrder) = attribute {
                                return sortOrder.order
                            }
                        }
                        return 0
                    }).max() ?? 0) + 1
                    importAttributes.append(.sortOrder(AccountSortOrderAttribute(order: nextSortOrder)))
                    let accountRecordId = transaction.createRecord(importAttributes)
                    print("Imported record \(accountRecordId) for \(backup.userId)")
                    restoredSessions += 1
                }
                |> deliverOnMainQueue
                
                let _ = importBackupSignal.start(completed: {
                    importNextBackup(index: index + 1)
                })
            }
            
            // Start the import chain
            importNextBackup(index: 0)
        })
        
        wrapperController?.present(controller, in: .window(.root), with: nil)
    }
    
    private func performDeleteAll() {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        let controller = textAlertController(context: context, title: "Delete All Backups?", text: "All sessions will be removed from Keychain.\n\nAccounts will not be logged out from Swiftgram.", actions: [
            TextAlertAction(type: .destructiveAction, title: presentationData.strings.Common_Delete, action: {
                let controller = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
                wrapperController?.present(controller, in: .window(.root), with: nil)
                do {
                    try KeychainBackupManager.shared.deleteAllSessions()
                    withAnimation {
                        sessions = getBackedSessions()
                    }
                    controller.dismiss()
                } catch let e {
                    print("Error deleting all sessions: \(e)")
                }
            }),
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {})
        ])
        
        wrapperController?.present(controller, in: .window(.root), with: nil)
    }
    
    private func performDelete(_ session: SessionBackup) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        let controller = textAlertController(context: context, title: "Delete 1 Backup?", text: "\(session.name ?? "\(session.userId)") session will be removed from Keychain.\n\nAccount will not be logged out from Swiftgram.", actions: [
            TextAlertAction(type: .destructiveAction, title: presentationData.strings.Common_Delete, action: {
                let controller = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
                wrapperController?.present(controller, in: .window(.root), with: nil)
                do {
                    try KeychainBackupManager.shared.deleteSession(for: "\(session.peerIdInternal)")
                    withAnimation {
                        sessions = getBackedSessions()
                    }
                    controller.dismiss()
                } catch let e {
                    print("Error deleting session: \(e)")
                }
            }),
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {})
        ])
        
        wrapperController?.present(controller, in: .window(.root), with: nil)
    }
    
    
    #if DEBUG
    private func performRemoveSessionFromApp(session: SessionBackup) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        let controller = textAlertController(context: context, title: "Remove session from App?", text: "\(session.name ?? "\(session.userId)") session will be removed from app? Account WILL BE logged out of Swiftgram.", actions: [
            TextAlertAction(type: .destructiveAction, title: presentationData.strings.Common_Delete, action: {
                let controller = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
                wrapperController?.present(controller, in: .window(.root), with: nil)
                
                let signal = context.sharedContext.accountManager.accountRecords()
                |> take(1)
                |> deliverOnMainQueue
                
                let _ = signal.start(next: { [weak controller] view in
                    
                    // Find record to delete
                    let accountRecord = view.records.first { record in
                        var userId: Int64 = 0
                        for attribute in record.attributes {
                            if case let .backupData(backupData) = attribute {
                                userId = backupData.data?.peerId ?? 0
                            }
                        }
                        return userId == session.peerIdInternal
                    }
                    
                    if let record = accountRecord {
                        let deleteSignal = context.sharedContext.accountManager.transaction { transaction -> Void in
                            transaction.updateRecord(record.id, { _ in return nil})
                        }
                        |> deliverOnMainQueue
                        
                        let _ = deleteSignal.start(next: {
                            withAnimation {
                                sessions = getBackedSessions()
                            }
                            controller?.dismiss()
                        })
                    } else {
                        controller?.dismiss()
                    }
                })
                
            }),
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {})
        ])
        
        wrapperController?.present(controller, in: .window(.root), with: nil)
    }
    #endif
    
    
    var body: some View {
        List {
            Section(header: Text("Actions")) {
                Button(action: performBackup) {
                    HStack {
                        Image(systemName: "key.fill")
                            .frame(width: 30)
                        Text("Backup to Keychain")
                        Spacer()
                    }
                }
                
                Button(action: performRestore) {
                    HStack {
                        Image(systemName: "arrow.2.circlepath")
                            .frame(width: 30)
                        Text("Restore from Keychain")
                        Spacer()
                    }
                }
                
                Button(action: performDeleteAll) {
                    HStack {
                        Image(systemName: "trash")
                            .frame(width: 30)
                        Text("Delete Keychain Backup")
                    }
                }
                .foregroundColor(.red)
//                Text("Removing sessions from Keychain. This will not affect logged-in accounts.")
//                    .font(.caption)
            }
            
            Section(header: Text("Backups")) {
                ForEach(sessions, id: \.peerIdInternal) { session in
                    SessionBackupRow(
                        backup: session,
                        isLoggedIn: loggedInPeerIDs.contains(session.peerIdInternal)
                    )
                    .contextMenu {
                        Button(action: {
                            performDelete(session)
                        }, label: {
                            HStack(spacing: 4) {
                                Text("Delete from Backup")
                                Image(systemName: "trash")
                            }
                        })
                        #if DEBUG
                        Button(action: {
                            performRemoveSessionFromApp(session: session)
                        }, label: {
                        
                            HStack(spacing: 4) {
                                Text("Remove from App")
                                Image(systemName: "trash")
                            }
                        })
                        #endif
                    }
                }
//                .onDelete { indexSet in
//                    performDelete(indexSet)
//                }
            }
        }
        .onAppear {
            withAnimation {
                sessions = getBackedSessions()
            }
            
            let accountsSignal = context.sharedContext.accountManager.accountRecords()
            |> deliverOnMainQueue
            
            loggedInAccountsDisposable = accountsSignal.start(next: { view in
                var result: [Int64] = []
                for record in view.records {
                    var isLoggedOut: Bool = false
                    var userId: Int64 = 0
                    for attribute in record.attributes {
                        if case .loggedOut = attribute  {
                            isLoggedOut = true
                        } else if case let .backupData(backupData) = attribute {
                            userId = backupData.data?.peerId ?? 0
                        }
                    }
                    
                    if !isLoggedOut && userId != 0 {
                        result.append(userId)
                    }
                }
  
                print("Will check logged in accounts")
                if loggedInPeerIDs != result {
                    print("Updating logged in accounts", result)
                    loggedInPeerIDs = result
                }
            })

        }
        .onDisappear {
            loggedInAccountsDisposable?.dispose()
        }
    }
    
}


func getBackedSessions() -> [SessionBackup] {
    var sessions: [SessionBackup] = []
    do {
        let backupSessionsData = try KeychainBackupManager.shared.getAllSessons()
        for sessionBackupData in backupSessionsData {
            do {
                let backup = try JSONDecoder().decode(SessionBackup.self, from: sessionBackupData)
                sessions.append(backup)
            } catch let e {
                print("IMPORT ERROR: \(e)")
            }
        }
    } catch let e {
        print("Error getting all sessions: \(e)")
    }
    return sessions
}


func backupSessionsFromView(_ view: AccountRecordsView<TelegramAccountManagerTypes>, accountsWithInfo: [AccountWithInfo] = []) {
    var recordsToBackup: [Int64: AccountRecord<TelegramAccountManagerTypes.Attribute>] = [:]
    for record in view.records {
        var sortOrder: Int32 = 0
        var isLoggedOut: Bool = false
        var isTestingEnvironment: Bool = false
        var peerId: Int64 = 0
        for attribute in record.attributes {
            if case let .sortOrder(value) = attribute {
                sortOrder = value.order
            } else if case .loggedOut = attribute  {
                isLoggedOut = true
            } else if case let .environment(environment) = attribute, case .test = environment.environment {
                isTestingEnvironment = true
            } else if case let .backupData(backupData) = attribute {
                peerId = backupData.data?.peerId ?? 0
            }
        }
        let _ = sortOrder
        let _ = isTestingEnvironment
        
        if !isLoggedOut && peerId != 0 {
            recordsToBackup[peerId] = record
        }
    }
    
    for (peerId, record) in recordsToBackup {
        var backupName: String? = nil
        if let accountWithInfo = accountsWithInfo.first(where: { $0.peer.id == PeerId(peerId) }) {
            if let user = accountWithInfo.peer as? TelegramUser {
                if let username = user.username {
                    backupName = "@\(username)"
                } else {
                    backupName = user.nameOrPhone
                }
            }
        }
        let backup = SessionBackup(name: backupName, accountRecord: record)
        do {
            let data = try JSONEncoder().encode(backup)
            try KeychainBackupManager.shared.saveSession(id: "\(backup.peerIdInternal)", data)
        } catch let e {
            print("BACKUP ERROR: \(e)")
        }
    }
}


@available(iOS 13.0, *)
public func sgSessionBackupManagerController(context: AccountContext, presentationData: PresentationData? = nil) -> ViewController {
    let theme = presentationData?.theme ?? (UITraitCollection.current.userInterfaceStyle == .dark ? defaultDarkColorPresentationTheme : defaultPresentationTheme)
    let strings = presentationData?.strings ?? defaultPresentationStrings

    let legacyController = LegacySwiftUIController(
        presentation: .navigation,
        theme: theme,
        strings: strings
    )
    legacyController.statusBar.statusBarStyle = theme.rootController
        .statusBarStyle.style
    legacyController.title = "Session Backup" //i18n("BackupManager.Title", strings.baseLanguageCode)

    let swiftUIView = SGSwiftUIView<SessionBackupManagerView>(
        navigationBarHeight: legacyController.navigationBarHeightModel,
        containerViewLayout: legacyController.containerViewLayoutModel,
        content: {
            SessionBackupManagerView(wrapperController: legacyController, context: context)
        }
    )
    let controller = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
    legacyController.bind(controller: controller)

    return legacyController
}


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
    @Binding var newKeyword: String
    let onAdd: () -> Void

    var body: some View {
        HStack {
            TextField("Enter keyword", text: $newKeyword)
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
                        
                        Text("Message Filter")
                            .font(.title)
                            .bold()
                        
                        Text("Remove distraction and reduce visibility of messages containing keywords below.\nKeywords are case-sensitive.")
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
                
                Section(header: Text("Keywords")) {
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
    let swiftUIView = MessageFilterView(wrapperController: legacyController)
    let controller = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
    legacyController.bind(controller: controller)

    return legacyController
}


private enum SGDebugControllerSection: Int32, SGItemListSection {
    case base
}

private enum SGDebugDisclosureLink: String {
    case sessionBackupManager
    case messageFilter
}

private enum SGDebugActions: String {
    case flexing
    case fileManager
    case clearRegDateCache
}

private enum SGDebugToggles: String {
    case forceImmediateShareSheet
    case legacyNotificationsFix
}


private typealias SGDebugControllerEntry = SGItemListUIEntry<SGDebugControllerSection, SGDebugToggles, AnyHashable, AnyHashable, SGDebugDisclosureLink, SGDebugActions>

private func SGDebugControllerEntries(presentationData: PresentationData) -> [SGDebugControllerEntry] {
    var entries: [SGDebugControllerEntry] = []
    
    let id = SGItemListCounter()
    #if DEBUG
    entries.append(.action(id: id.count, section: .base, actionType: .flexing, text: "FLEX", kind: .generic))
    entries.append(.action(id: id.count, section: .base, actionType: .fileManager, text: "FileManager", kind: .generic))
    #endif
    
    if SGSimpleSettings.shared.b {
        entries.append(.disclosure(id: id.count, section: .base, link: .sessionBackupManager, text: "Session Backup"))
        entries.append(.disclosure(id: id.count, section: .base, link: .messageFilter, text: "Message Filter"))
    }
    entries.append(.action(id: id.count, section: .base, actionType: .clearRegDateCache, text: "Clear Regdate cache", kind: .generic))
    entries.append(.toggle(id: id.count, section: .base, settingName: .forceImmediateShareSheet, value: SGSimpleSettings.shared.forceSystemSharing, text: "Force System Share Sheet", enabled: true))
    entries.append(.toggle(id: id.count, section: .base, settingName: .legacyNotificationsFix, value: SGSimpleSettings.shared.legacyNotificationsFix, text: "[Legacy] Fix empty notifications", enabled: true))
    
    return entries
}
private func okUndoController(_ text: String, _ presentationData: PresentationData) -> UndoOverlayController {
    return UndoOverlayController(presentationData: presentationData, content: .succeed(text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false })
}


public func sgDebugController(context: AccountContext) -> ViewController {
    var presentControllerImpl: ((ViewController, ViewControllerPresentationArguments?) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

    let simplePromise = ValuePromise(true, ignoreRepeated: false)
    
    let arguments = SGItemListArguments<SGDebugToggles, AnyHashable, AnyHashable, SGDebugDisclosureLink, SGDebugActions>(context: context, setBoolValue: { toggleName, value in
        switch toggleName {
            case .forceImmediateShareSheet:
                SGSimpleSettings.shared.forceSystemSharing = value
            case .legacyNotificationsFix:
                SGSimpleSettings.shared.legacyNotificationsFix = value
        }
    }, openDisclosureLink: { link in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        switch (link) {
            case .sessionBackupManager:
                if #available(iOS 13.0, *) {
                    pushControllerImpl?(sgSessionBackupManagerController(context: context, presentationData: presentationData))
                } else {
                    presentControllerImpl?(UndoOverlayController(
                        presentationData: presentationData,
                        content: .info(title: nil, text: "Update OS to access this feature", timeout: nil, customUndoText: nil),
                        elevatedLayout: false,
                        action: { _ in return false }
                    ), nil)
                }
        case .messageFilter:
                if #available(iOS 13.0, *) {
                    pushControllerImpl?(sgMessageFilterController(presentationData: presentationData))
                } else {
                    presentControllerImpl?(UndoOverlayController(
                        presentationData: presentationData,
                        content: .info(title: nil, text: "Update OS to access this feature", timeout: nil, customUndoText: nil),
                        elevatedLayout: false,
                        action: { _ in return false }
                    ), nil)
                }
        }
    }, action: { actionType in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        switch actionType {
            case .clearRegDateCache:
                SGLogger.shared.log("SGDebug", "Regdate cache cleanup init")
                
                /*
                let spinner = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))

                presentControllerImpl?(spinner, nil)
                */
                SGSimpleSettings.shared.regDateCache.drop()
                SGLogger.shared.log("SGDebug", "Regdate cache cleanup succesfull")
                presentControllerImpl?(okUndoController("OK: Regdate cache cleaned", presentationData), nil)
                /*
                Queue.mainQueue().async() { [weak spinner] in
                    spinner?.dismiss()
                }
                */
        case .flexing:
            #if DEBUG
            FLEXManager.shared.toggleExplorer()
            #endif
        case .fileManager:
            #if DEBUG
            let baseAppBundleId = Bundle.main.bundleIdentifier!
            let appGroupName = "group.\(baseAppBundleId)"
            let maybeAppGroupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupName)
            if let maybeAppGroupUrl = maybeAppGroupUrl {
                if let fileManager = FLEXFileBrowserController(path: maybeAppGroupUrl.path) {
                    FLEXManager.shared.showExplorer()
                    let flexNavigation = FLEXNavigationController(rootViewController: fileManager)
                    FLEXManager.shared.presentTool({ return flexNavigation })
                }
            } else {
                presentControllerImpl?(UndoOverlayController(
                    presentationData: presentationData,
                    content: .info(title: nil, text: "Empty path", timeout: nil, customUndoText: nil),
                    elevatedLayout: false,
                    action: { _ in return false }
                ),
                nil)
            }
            #endif
        }
    })
    
    let signal = combineLatest(context.sharedContext.presentationData, simplePromise.get())
    |> map { presentationData, _ ->  (ItemListControllerState, (ItemListNodeState, Any)) in
        
        let entries = SGDebugControllerEntries(presentationData: presentationData)
        
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Swiftgram Debug"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, ensureVisibleItemTag: /*focusOnItemTag*/ nil, initialScrollToItem: nil /* scrollToItem*/ )
        
        return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c, a in
        controller?.present(c, in: .window(.root), with: a)
    }
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    // Workaround
    let _ = pushControllerImpl
    
    return controller
}


