// MARK: Swiftgram
import SGLogging
import SGAppGroupIdentifier
import SGSimpleSettings
import SwiftSignalKit
import TelegramUIPreferences
import AccountContext
import Postbox
import Foundation

extension SharedAccountContextImpl {
    // MARK: Swiftgram
    func performSGUISettingsMigrationIfNecessary() {
        if self.didPerformSGUISettingsMigration {
            return
        }
        let sgMigrationKey = "sg_migrated_sgui_settings_v1"
        if UserDefaults.standard.bool(forKey: sgMigrationKey) {
            self.didPerformSGUISettingsMigration = true
            return
        }
        guard let sgPrimary = self.sgPrimaryAccountContextForMigration() else {
            return
        }
        self.didPerformSGUISettingsMigration = true
        
        let sgPreferences: Signal<PreferencesView, NoError> = sgPrimary.account.postbox.preferencesView(keys: [ApplicationSpecificPreferencesKeys.SGUISettings])
        let _ = (sgPreferences
        |> take(1)
        |> deliverOnMainQueue).start(next: { view in
            let sgSettings: SGUISettings = view.values[ApplicationSpecificPreferencesKeys.SGUISettings]?.get(SGUISettings.self) ?? .default
            let sgDefaults = UserDefaults.standard
            let sgDomainName = sgBaseBundleIdentifier()
            let sgDomain = sgDefaults.persistentDomain(forName: sgDomainName) ?? [:]
            if sgDomain[SGSimpleSettings.Keys.hideStories.rawValue] == nil {
                SGSimpleSettings.shared.hideStories = sgSettings.hideStories
                SGLogger.shared.log("SGSimpleSettings", "Migrated hideStories: \(sgSettings.hideStories)")
            }
            if sgDomain[SGSimpleSettings.Keys.warnOnStoriesOpen.rawValue] == nil {
                SGSimpleSettings.shared.warnOnStoriesOpen = sgSettings.warnOnStoriesOpen
                SGLogger.shared.log("SGSimpleSettings", "Migrated warnOnStoriesOpen: \(sgSettings.warnOnStoriesOpen)")
            }
            if sgDomain[SGSimpleSettings.Keys.showProfileId.rawValue] == nil {
                SGSimpleSettings.shared.showProfileId = sgSettings.showProfileId
                SGLogger.shared.log("SGSimpleSettings", "Migrated showProfileId: \(sgSettings.showProfileId)")
            }
            if sgDomain[SGSimpleSettings.Keys.sendWithReturnKey.rawValue] == nil {
                SGSimpleSettings.shared.sendWithReturnKey = sgSettings.sendWithReturnKey
                SGLogger.shared.log("SGSimpleSettings", "Migrated sendWithReturnKey: \(sgSettings.sendWithReturnKey)")
            }
            sgDefaults.set(true, forKey: sgMigrationKey)
        })
    }
}
