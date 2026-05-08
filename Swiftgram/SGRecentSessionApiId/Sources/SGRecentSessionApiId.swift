import Foundation
import BuildConfig
import TelegramCore

public enum SGRecentSessionApiId {
    public static func string(for session: RecentAccountSession) -> String? {
        guard !session.isCurrent, let baseAppBundleId = Bundle.main.bundleIdentifier else {
            return nil
        }
        let buildConfig = BuildConfig(baseAppBundleId: baseAppBundleId)
        guard buildConfig.apiId != session.apiId else {
            return nil
        }
        return String(session.apiId)
    }
}
