import SGAppGroupIdentifier
import SGLogging
import UIKit
import Foundation

private let dbResetKey = "sg_db_reset"
private let dbHardResetKey = "sg_db_hard_reset"

private func sgDefaultDataPath() -> String? {
    guard let appGroupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sgAppGroupIdentifier()) else {
        return nil
    }
    return (appGroupUrl.path as NSString).appendingPathComponent("telegram-data")
}

public func sgDBResetIfNeeded(databasePath: String, present: ((UIViewController) -> ())?) {
    guard UserDefaults.standard.bool(forKey: dbResetKey) else {
        return
    }
    NSLog("[SG.DBReset] Resetting DB with system settings")
    let alert = UIAlertController(
        title: "Metadata Reset.\nDO NOT CLOSE THE APP\nPlease wait...",
        message: nil,
        preferredStyle: .alert
    )
    present?(alert)
    do {
        let _ = try FileManager.default.removeItem(atPath: databasePath)
        NSLog("[SG.DBReset] Done. Reset completed")
        let successAlert = UIAlertController(
            title: "Metadata Reset completed",
            message: nil,
            preferredStyle: .alert
        )
        successAlert.addAction(UIAlertAction(title: "Restart App", style: .cancel) { _ in
            exit(0)
        })
        successAlert.addAction(UIAlertAction(title: "OK", style: .default))
        alert.dismiss(animated: false) {
            present?(successAlert)
        }
    } catch {
        NSLog("[SG.DBReset] ERROR. Failed to reset database: \(error)")
        let failAlert = UIAlertController(
            title: "ERROR. Failed to Reset database",
            message: "\(error)",
            preferredStyle: .alert
        )
        alert.dismiss(animated: false) {
            present?(failAlert)
        }
    }
    UserDefaults.standard.set(false, forKey: dbResetKey)
//    let semaphore = DispatchSemaphore(value: 0)
//    semaphore.wait()
}

@discardableResult
public func sgHardReset(dataPath: String? = nil, present: ((UIViewController) -> ())?, beforePresent: (() -> ())? = nil) -> Bool {
    guard UserDefaults.standard.bool(forKey: dbHardResetKey) else {
        return false
    }
    UserDefaults.standard.set(false, forKey: dbHardResetKey)
    beforePresent?()
    guard let dataPath = dataPath ?? sgDefaultDataPath() else {
        NSLog("[SG.DBReset] ERROR. Reset All failed: Error 2")
        let failAlert = UIAlertController(
            title: "ERROR. Reset All failed",
            message: "Error 2",
            preferredStyle: .alert
        )
        present?(failAlert)
        return true
    }
    let startAlert = UIAlertController(
        title: "ATTENTION",
        message: "Confirm RESET ALL?",
        preferredStyle: .alert
    )
    
    startAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
        exit(0)
    })
    startAlert.addAction(UIAlertAction(title: "RESET", style: .destructive) { _ in
        let ensureAlert = UIAlertController(
            title: "⚠️ ATTENTION ⚠️",
            message: "ARE YOU SURE you want to make a RESET ALL?",
            preferredStyle: .alert
        )
        
        ensureAlert.addAction(UIAlertAction(title: "Cancel", style: .default) { _ in
            exit(0)
        })
        ensureAlert.addAction(UIAlertAction(title: "RESET NOW", style: .destructive) { _ in
            NSLog("[SG.DBReset] Reset All with system settings")
            let alert = UIAlertController(
                title: "Reset All.\nDO NOT CLOSE THE APP\nPlease wait...",
                message: nil,
                preferredStyle: .alert
            )
            ensureAlert.dismiss(animated: false) {
                present?(alert)
            }
            
            do {
                let fileManager = FileManager.default
                for metadataItem in ["db", "guard_db", "media", "spotlight"] {
                    let metadataItemPath = (dataPath as NSString).appendingPathComponent("accounts-metadata/\(metadataItem)")
                    if fileManager.fileExists(atPath: metadataItemPath) {
                        NSLog("[SG.DBReset] Trying to delete accounts-metadata/\(metadataItem)")
                        try fileManager.removeItem(atPath: metadataItemPath)
                        NSLog("[SG.DBReset] OK. Deleted accounts-metadata/\(metadataItem)")
                    }
                }
                let contents = try fileManager.contentsOfDirectory(atPath: dataPath)

                // Filter directories that match our criteria
                let accountDirectories = contents.compactMap { filename in
                    let fullPath = (dataPath as NSString).appendingPathComponent(filename)
                    
                    var isDirectory: ObjCBool = false
                    if fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory), isDirectory.boolValue {
                        if filename.hasPrefix("account-") {
                            return fullPath
                        }
                    }
                    return nil
                }

                NSLog("[SG.DBReset] Found \(accountDirectories.count) account dirs...")
                var deletedPostboxCount = 0
                for accountDir in accountDirectories {
                    let accountName = (accountDir as NSString).lastPathComponent
                    let postboxPath = (accountDir as NSString).appendingPathComponent("postbox")
                    
                    var isPostboxDir: ObjCBool = false
                    if fileManager.fileExists(atPath: postboxPath, isDirectory: &isPostboxDir), isPostboxDir.boolValue {
                        // Delete postbox/db
                        let dbPath = (postboxPath as NSString).appendingPathComponent("db")
                        var isDbDir: ObjCBool = false
                        if fileManager.fileExists(atPath: dbPath, isDirectory: &isDbDir), isDbDir.boolValue {
                            NSLog("[SG.DBReset] Trying to delete postbox/db in: \(accountName)")
                            try fileManager.removeItem(atPath: dbPath)
                            NSLog("[SG.DBReset] OK. Deleted postbox/db directory in: \(accountName)")
                        }
                        
                        // Delete postbox/media
                        let mediaPath = (postboxPath as NSString).appendingPathComponent("media")
                        var isMediaDir: ObjCBool = false
                        if fileManager.fileExists(atPath: mediaPath, isDirectory: &isMediaDir), isMediaDir.boolValue {
                            NSLog("[SG.DBReset] Trying to delete postbox/media in: \(accountName)")
                            try fileManager.removeItem(atPath: mediaPath)
                            NSLog("[SG.DBReset] OK. Deleted postbox/media directory in: \(accountName)")
                        }
                        
                        deletedPostboxCount += 1
                    }
                }


                NSLog("[SG.DBReset] Done. Reset All completed")
                let successAlert = UIAlertController(
                    title: "Reset All completed",
                    message: nil,
                    preferredStyle: .alert
                )
                successAlert.addAction(UIAlertAction(title: "Restart App", style: .cancel) { _ in
                    exit(0)
                })
                alert.dismiss(animated: false) {
                    present?(successAlert)
                }
            } catch {
                NSLog("[SG.DBReset] ERROR. Reset All failed: \(error)")
                let failAlert = UIAlertController(
                    title: "ERROR. Reset All failed",
                    message: "\(error)",
                    preferredStyle: .alert
                )
                alert.dismiss(animated: false) {
                    present?(failAlert)
                }
            }
        })
        ensureAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            exit(0)
        })
        
        present?(ensureAlert)
    })
             
    present?(startAlert)
    return true
}
