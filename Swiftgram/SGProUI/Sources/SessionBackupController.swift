import Foundation
import UndoUI
import AccountContext
import TelegramCore
import Postbox
import Display
import SwiftSignalKit
import TelegramPresentationData
import PresentationDataUtils
import SGSimpleSettings
import SGLogging
import SGKeychainBackupManager

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
    @Environment(\.lang) var lang: String
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
                
                Text("SessionBackup.LastBackupAt".i18n(lang, args: formattedDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text((isLoggedIn ? "SessionBackup.LoggedIn" : "SessionBackup.LoggedOut").i18n(lang))
                .font(.caption)
                .foregroundColor(isLoggedIn ? .white : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(isLoggedIn ? Color.accentColor : Color.secondary.opacity(0.1))
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
    @Environment(\.lang) var lang: String
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
            if let result = try? await combineLatest(signal, signal2).awaitable() {
                let (view, accountsWithInfo) = result
                backupSessionsFromView(view, accountsWithInfo: accountsWithInfo.1)
                withAnimation {
                    sessions = getBackedSessions()
                }
                controller.dismiss()
            }
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
                        okUndoController("SessionBackup.RestoreOK".i18n(lang, args: "\(restoredSessions)"), presentationData),
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
                    SGLogger.shared.log("SessionBackup", "Record \(backup.userId) already exists, skipping")
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
                    SGLogger.shared.log("SessionBackup", "Imported record \(accountRecordId) for \(backup.userId)")
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
        
        let controller = textAlertController(context: context, title: "SessionBackup.DeleteAll.Title".i18n(lang), text: "SessionBackup.DeleteAll.Text".i18n(lang), actions: [
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
                    SGLogger.shared.log("SessionBackup", "Error deleting all sessions: \(e)")
                }
            }),
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {})
        ])
        
        wrapperController?.present(controller, in: .window(.root), with: nil)
    }
    
    private func performDelete(_ session: SessionBackup) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        let controller = textAlertController(context: context, title: "SessionBackup.DeleteSingle.Title".i18n(lang), text: "SessionBackup.DeleteSingle.Text".i18n(lang, args: "\(session.name ?? "\(session.userId)")"), actions: [
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
                    SGLogger.shared.log("SessionBackup", "Error deleting session: \(e)")
                }
            }),
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_Cancel, action: {})
        ])
        
        wrapperController?.present(controller, in: .window(.root), with: nil)
    }
    
    
    private func performRemoveSessionFromApp(session: SessionBackup) {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        let controller = textAlertController(context: context, title: "SessionBackup.RemoveFromApp.Title".i18n(lang), text: "SessionBackup.RemoveFromApp.Text".i18n(lang, args: "\(session.name ?? "\(session.userId)")"), actions: [
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
    
    
    var body: some View {
        List {
            Section() {
                Button(action: performBackup) {
                    HStack {
                        Image(systemName: "key.fill")
                            .frame(width: 30)
                        Text("SessionBackup.Actions.Backup".i18n(lang))
                        Spacer()
                    }
                }
                
                Button(action: performRestore) {
                    HStack {
                        Image(systemName: "arrow.2.circlepath")
                            .frame(width: 30)
                        Text("SessionBackup.Actions.Restore".i18n(lang))
                        Spacer()
                    }
                }
                
                Button(action: performDeleteAll) {
                    HStack {
                        Image(systemName: "trash")
                            .frame(width: 30)
                        Text("SessionBackup.Actions.DeleteAll".i18n(lang))
                    }
                }
                .foregroundColor(.red)
                
            }
            
            Text("SessionBackup.Notice".i18n(lang))
                .font(.caption)
                .foregroundColor(.secondary)
            
            Section(header: Text("SessionBackup.Sessions.Title".i18n(lang))) {
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
                                Text("SessionBackup.Actions.DeleteOne".i18n(lang))
                                Image(systemName: "trash")
                            }
                        })
                        Button(action: {
                            performRemoveSessionFromApp(session: session)
                        }, label: {
                        
                            HStack(spacing: 4) {
                                Text("SessionBackup.Actions.RemoveFromApp".i18n(lang))
                                Image(systemName: "trash")
                            }
                        })
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
  
                SGLogger.shared.log("SessionBackup", "Logged in accounts: \(result)")
                if loggedInPeerIDs != result {
                    SGLogger.shared.log("SessionBackup", "Updating logged in accounts: \(result)")
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
                SGLogger.shared.log("SessionBackup", "IMPORT ERROR: \(e)")
            }
        }
    } catch let e {
        SGLogger.shared.log("SessionBackup", "Error getting all sessions: \(e)")
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
            SGLogger.shared.log("SessionBackup", "BACKUP ERROR: \(e)")
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
    legacyController.title = "SessionBackup.Title".i18n(strings.baseLanguageCode)

    let swiftUIView = SGSwiftUIView<SessionBackupManagerView>(
        legacyController: legacyController,
        manageSafeArea: true,
        content: {
            SessionBackupManagerView(wrapperController: legacyController, context: context)
        }
    )
    let controller = UIHostingController(rootView: swiftUIView, ignoreSafeArea: true)
    legacyController.bind(controller: controller)

    return legacyController
}
