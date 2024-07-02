import UIKit
import Foundation
import SGLogging

private let dbResetKey = "sg_db_reset"

public func sgDBResetIfNeeded(databasePath: String, present: ((UIViewController) -> ())?) {
    guard UserDefaults.standard.bool(forKey: dbResetKey) else {
        return
    }
    NSLog("[SG.DBReset] Resetting DB with system settings")
    let alert = UIAlertController(
        title: "Database reset.\nPlease wait...",
        message: nil,
        preferredStyle: .alert
    )
    present?(alert)
    do {
        let _ = try FileManager.default.removeItem(atPath: databasePath)
        NSLog("[SG.DBReset] Done. Reset completed")
        let successAlert = UIAlertController(
            title: "Database reset completed",
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
            title: "ERROR. Failed to reset database",
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
