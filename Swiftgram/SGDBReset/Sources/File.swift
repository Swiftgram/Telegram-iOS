import SGAppGroupIdentifier
import UIKit
import Foundation

private let dbResetKey = "sg_db_reset"
private let dbHardResetKey = "sg_db_hard_reset"

public typealias SGResetPresenter = (UIViewController, @escaping () -> Void) -> Void

private func sgDefaultDataPath() throws -> String {
    NSLog("[SG.DBReset] Resolving app-group container")
    guard let appGroupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sgAppGroupIdentifier()) else {
        throw NSError(domain: "SG.DBReset", code: 2, userInfo: [NSLocalizedDescriptionKey: "The app-group container is unavailable. Unlock the device and restart the app to retry."])
    }
    return (appGroupUrl.path as NSString).appendingPathComponent("telegram-data")
}

private func sgRemoveResetItem(atPath path: String) throws {
    do {
        NSLog("[SG.DBReset] Deleting \((path as NSString).lastPathComponent)")
        try FileManager.default.removeItem(atPath: path)
    } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
        // A missing item is already reset, including after an interrupted reset.
    }
}

private func sgPerformReset(dataPath: String?, hardReset: Bool, present: @escaping SGResetPresenter) {
    let alert = UIAlertController(
        title: hardReset ? "Reset All" : "Metadata Reset",
        message: "DO NOT CLOSE THE APP\nPlease wait...",
        preferredStyle: .alert
    )
    present(alert) {
        sgResetFiles(dataPath: dataPath, hardReset: hardReset) { failure in
            let title: String
            let message: String
            if let failure = failure {
                NSLog("[SG.DBReset] ERROR. Reset failed: \(failure)")
                title = "ERROR. Reset failed"
                message = "\(failure)\n\nThe reset is still enabled. Restart the app to retry, or disable it in iOS Settings."
            } else {
                NSLog("[SG.DBReset] Reset completed; restart required")
                UserDefaults.standard.set(false, forKey: hardReset ? dbHardResetKey : dbResetKey)
                if hardReset {
                    UserDefaults.standard.set(false, forKey: dbResetKey)
                }
                title = hardReset ? "Reset All completed" : "Metadata Reset completed"
                message = "Restart the app to continue."
            }
            let resultAlert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            resultAlert.addAction(UIAlertAction(title: "Close App", style: .default) { _ in
                exit(0)
            })
            alert.dismiss(animated: false) {
                present(resultAlert, {})
            }
        }
    }
}

private func sgResetFiles(dataPath: String?, hardReset: Bool, completion: @escaping (Error?) -> Void) {
    // Container lookup and recursive deletion must never block launch or the recovery UI.
    DispatchQueue.global(qos: .userInitiated).async {
        let failure: Error?
        do {
            let rootPath = try dataPath ?? sgDefaultDataPath()
            if hardReset {
                let fileManager = FileManager.default
                let contents: [String]
                do {
                    contents = try fileManager.contentsOfDirectory(atPath: rootPath)
                } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                    contents = []
                }
                for filename in contents where filename.hasPrefix("account-") {
                    let accountPath = (rootPath as NSString).appendingPathComponent(filename)
                    var isDirectory: ObjCBool = false
                    guard fileManager.fileExists(atPath: accountPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                        continue
                    }
                    // Reclaim media first, before touching databases on an almost-full volume.
                    for item in ["media", "db"] {
                        try sgRemoveResetItem(atPath: (accountPath as NSString).appendingPathComponent("postbox/\(item)"))
                    }
                }
                for item in ["media", "db", "guard_db", "spotlight"] {
                    try sgRemoveResetItem(atPath: (rootPath as NSString).appendingPathComponent("accounts-metadata/\(item)"))
                }
            } else {
                try sgRemoveResetItem(atPath: (rootPath as NSString).appendingPathComponent("accounts-metadata/db"))
            }
            failure = nil
        } catch {
            failure = error
        }

        DispatchQueue.main.async {
            completion(failure)
        }
    }
}

// Called before account-manager initialization; never delete an open metadata database.
@discardableResult
public func sgDBResetIfNeeded(dataPath: String? = nil, present: SGResetPresenter?, beforePresent: (() -> ())? = nil) -> Bool {
    guard UserDefaults.standard.bool(forKey: dbResetKey) else {
        return false
    }
    NSLog("[SG.DBReset] Entering metadata recovery before database startup")
    beforePresent?()
    if let present = present {
        DispatchQueue.main.async {
            sgPerformReset(dataPath: dataPath, hardReset: false, present: present)
        }
    }
    return true
}

@discardableResult
public func sgHardReset(dataPath: String? = nil, present: SGResetPresenter?, beforePresent: (() -> ())? = nil) -> Bool {
    guard UserDefaults.standard.bool(forKey: dbHardResetKey) else {
        return false
    }
    NSLog("[SG.DBReset] Entering hard-reset recovery before container lookup")
    beforePresent?()
    guard let present = present else {
        return true
    }
    let cancel: (UIAlertAction) -> Void = { _ in
        UserDefaults.standard.set(false, forKey: dbHardResetKey)
        exit(0)
    }
    let startAlert = UIAlertController(
        title: "ATTENTION",
        message: "Confirm RESET ALL? This removes local databases and downloaded media for all accounts. Local-only data cannot be recovered.",
        preferredStyle: .alert
    )
    startAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: cancel))
    startAlert.addAction(UIAlertAction(title: "RESET", style: .destructive) { _ in
        let ensureAlert = UIAlertController(
            title: "⚠️ ATTENTION ⚠️",
            message: "ARE YOU SURE you want to make a RESET ALL?",
            preferredStyle: .alert
        )
        ensureAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: cancel))
        ensureAlert.addAction(UIAlertAction(title: "RESET NOW", style: .destructive) { _ in
            ensureAlert.dismiss(animated: false) {
                sgPerformReset(dataPath: dataPath, hardReset: true, present: present)
            }
        })
        startAlert.dismiss(animated: false) {
            present(ensureAlert, {})
        }
    })
    // Let didFinishLaunching return before presenting UIKit recovery controls.
    DispatchQueue.main.async {
        present(startAlert, {})
    }
    return true
}
