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

private final class SGResetProgress {
    private let lock = NSLock()
    private var operation = "Waiting for recovery UI"
    private var removedItems = 0
    private var lastRemovalTime = Date()
    private let startTime = Date()

    func update(_ operation: String? = nil, removedItem: Bool = false) {
        self.lock.lock()
        if let operation = operation {
            self.operation = operation
        }
        if removedItem {
            self.removedItems += 1
            self.lastRemovalTime = Date()
        }
        self.lock.unlock()
    }

    func message() -> String {
        self.lock.lock()
        let operation = self.operation
        let removedItems = self.removedItems
        let idleSeconds = Int(Date().timeIntervalSince(self.lastRemovalTime))
        self.lock.unlock()
        let elapsedSeconds = Int(Date().timeIntervalSince(self.startTime))
        return "DO NOT CLOSE THE APP\n\n\(operation)\nItems removed: \(removedItems)\nElapsed: \(elapsedSeconds)s\nSince last removal: \(idleSeconds)s\n\nLarge media folders can take several minutes."
    }
}

private func sgRemoveResetItem(atPath path: String, progress: SGResetProgress? = nil) throws {
    let url = URL(fileURLWithPath: path)
    let fileManager = FileManager.default
    let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]

    func remove(_ url: URL) throws {
        do {
            // Do not descend into symbolic links. Stream children without a full directory inventory.
            let values = try url.resourceValues(forKeys: keys)
            if values.isDirectory == true && values.isSymbolicLink != true {
                var enumerationError: Error?
                guard let children = fileManager.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants], errorHandler: { _, error in
                    enumerationError = error
                    return false
                }) else {
                    throw NSError(domain: "SG.DBReset", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to list reset folder: \(url.lastPathComponent)"])
                }
                for case let child as URL in children {
                    try remove(child)
                }
                if let enumerationError = enumerationError {
                    throw enumerationError
                }
            }
            try fileManager.removeItem(at: url)
            progress?.update(removedItem: true)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
            // A vanished child must not skip its remaining siblings.
        }
    }

    // Only expose the account/category, not individual media names, in periodic logs.
    let components = url.pathComponents.suffix(3).joined(separator: "/")
    NSLog("[SG.DBReset] Starting deletion: \(components)")
    progress?.update("Removing \(components)")
    do {
        try remove(url)
        NSLog("[SG.DBReset] Finished deletion: \(components)")
    } catch let error as NSError where error.domain == NSCocoaErrorDomain && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
        // A missing item is already reset, including after an interrupted reset.
        NSLog("[SG.DBReset] Already absent: \(components)")
    }
}

private func sgPerformReset(dataPath: String?, hardReset: Bool, present: @escaping SGResetPresenter) {
    let alert = UIAlertController(
        title: hardReset ? "Reset All" : "Metadata Reset",
        message: "DO NOT CLOSE THE APP\nPlease wait...",
        preferredStyle: .alert
    )
    let progress = SGResetProgress()
    let timer = Timer(timeInterval: 1.0, repeats: true) { [weak alert] _ in
        alert?.message = progress.message()
    }
    RunLoop.main.add(timer, forMode: .common)
    let heartbeat = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
    heartbeat.schedule(deadline: .now() + 10.0, repeating: 10.0)
    heartbeat.setEventHandler {
        NSLog("[SG.DBReset] Progress: \(progress.message())")
    }
    heartbeat.resume()
    NSLog("[SG.DBReset] Presenting progress UI")
    present(alert) {
        NSLog("[SG.DBReset] Progress UI presented; starting worker")
        sgResetFiles(dataPath: dataPath, hardReset: hardReset, progress: progress) { failure in
            timer.invalidate()
            heartbeat.cancel()
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

private func sgResetFiles(dataPath: String?, hardReset: Bool, progress: SGResetProgress? = nil, completion: @escaping (Error?) -> Void) {
    // Container lookup and recursive deletion must never block launch or the recovery UI.
    DispatchQueue.global(qos: .userInitiated).async {
        let failure: Error?
        do {
            progress?.update("Resolving app-group container")
            let rootPath = try dataPath ?? sgDefaultDataPath()
            NSLog("[SG.DBReset] Data root resolved")
            if hardReset {
                progress?.update("Listing account folders")
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
                        try sgRemoveResetItem(atPath: (accountPath as NSString).appendingPathComponent("postbox/\(item)"), progress: progress)
                    }
                }
                for item in ["media", "db", "guard_db", "spotlight"] {
                    try sgRemoveResetItem(atPath: (rootPath as NSString).appendingPathComponent("accounts-metadata/\(item)"), progress: progress)
                }
            } else {
                try sgRemoveResetItem(atPath: (rootPath as NSString).appendingPathComponent("accounts-metadata/db"), progress: progress)
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
