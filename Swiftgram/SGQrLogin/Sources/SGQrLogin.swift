import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import AccountContext
import GlassBarButtonComponent
import ComponentFlow
import BundleIconComponent

public func sgExportQrLoginToken(account: UnauthorizedAccount, sharedContext: SharedAccountContext) -> Signal<ExportAuthTransferTokenResult, ExportAuthTransferTokenError> {
    return sharedContext.activeAccountContexts
    |> castError(ExportAuthTransferTokenError.self)
    |> take(1)
    |> mapToSignal { activeAccountsAndInfo -> Signal<ExportAuthTransferTokenResult, ExportAuthTransferTokenError> in
        let (_, activeAccounts, _) = activeAccountsAndInfo
        let activeProductionUserIds = activeAccounts.map({ $0.1.account }).filter({ !$0.testingEnvironment }).map({ $0.peerId.id })
        let activeTestingUserIds = activeAccounts.map({ $0.1.account }).filter({ $0.testingEnvironment }).map({ $0.peerId.id })

        return TelegramEngineUnauthorized(account: account).auth.exportAuthTransferToken(accountManager: sharedContext.accountManager, otherAccountUserIds: account.testingEnvironment ? activeTestingUserIds : activeProductionUserIds, syncContacts: true)
    }
}

// MARK: Swiftgram
// .authKeyUnregistered is a transient auth-key race after QR login's DC migration.
// Redoing the export/import round trip and resubmitting the password resolves it,
// usually in under two seconds.
public func sgAuthorizeWithPasswordRetryingQrLogin(
    sharedContext: SharedAccountContext,
    account: UnauthorizedAccount,
    password: String,
    syncContacts: Bool,
    maxRetries: Int = 8,
    retryDelay: Double = 1.5,
    retryDelayIncrement: Double = 1.0,
    maxRetryDelay: Double = 6.0,
    accountUpdated: @escaping (UnauthorizedAccount) -> Void
) -> Signal<Void, AuthorizationPasswordVerificationError> {
    return Signal { subscriber in
        let disposable = MetaDisposable()

        func attemptPassword(account: UnauthorizedAccount, retriesLeft: Int) {
            disposable.set(authorizeWithPassword(accountManager: sharedContext.accountManager, account: account, password: password, syncContacts: syncContacts).startStrict(error: { error in
                guard case .authKeyUnregistered = error, retriesLeft > 0 else {
                    subscriber.putError(error)
                    return
                }
                retryQrExportImport(account: account, retriesLeft: retriesLeft)
            }, completed: {
                subscriber.putCompletion()
            }))
        }

        func retryQrExportImport(account: UnauthorizedAccount, retriesLeft: Int) {
            guard retriesLeft > 0 else {
                subscriber.putError(.authKeyUnregistered)
                return
            }
            disposable.set(sgExportQrLoginToken(account: account, sharedContext: sharedContext).startStrict(next: { result in
                switch result {
                case let .passwordRequested(newAccount):
                    accountUpdated(newAccount)
                    attemptPassword(account: newAccount, retriesLeft: retriesLeft - 1)
                case let .changeAccountAndRetry(newAccount):
                    accountUpdated(newAccount)
                    retryQrExportImport(account: newAccount, retriesLeft: retriesLeft - 1)
                case .loggedIn:
                    subscriber.putCompletion()
                case .displayToken:
                    subscriber.putError(.authKeyUnregistered)
                }
            }, error: { error in
                switch error {
                case .authKeyUnregistered, .authTokenExpired:
                    let attemptIndex = maxRetries - retriesLeft
                    let currentDelay = min(maxRetryDelay, retryDelay + Double(attemptIndex) * retryDelayIncrement)
                    disposable.set((Signal<Never, NoError>.complete()
                    |> delay(currentDelay, queue: .mainQueue())).startStrict(completed: {
                        retryQrExportImport(account: account, retriesLeft: retriesLeft - 1)
                    }))
                case .limitExceeded:
                    subscriber.putError(.limitExceeded)
                case .generic:
                    subscriber.putError(.generic)
                }
            }))
        }

        attemptPassword(account: account, retriesLeft: maxRetries)

        return disposable
    }
}

public func sgQrLoginBarButtonNode(theme: PresentationTheme, action: @escaping (UIView) -> Void) -> BarComponentHostNode {
    let size = CGSize(width: 40.0, height: 40.0)
    return BarComponentHostNode(
        component: AnyComponentWithIdentity(id: "qrLogin", component: AnyComponent(
            GlassBarButtonComponent(
                size: size,
                backgroundColor: nil,
                isDark: theme.overallDarkAppearance,
                state: .glass,
                component: AnyComponentWithIdentity(id: "qrLoginIcon", component: AnyComponent(
                    BundleIconComponent(
                        name: "Settings/QrIcon",
                        tintColor: theme.chat.inputPanel.panelControlColor
                    )
                )),
                action: action
            )
        )),
        size: size
    )
}
