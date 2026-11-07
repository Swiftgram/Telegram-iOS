import SGSimpleSettings

import Foundation
import Postbox
import SwiftSignalKit

private var sgDismissedSuggestionsPromise = ValuePromise<Set<String>>(Set())
private var sgDismissedSuggestions: Set<String> = Set() {
    didSet {
        sgDismissedSuggestionsPromise.set(sgDismissedSuggestions)
    }
}

public func dismissSGProvidedSuggestion(suggestionId: String) {
    sgDismissedSuggestions.insert(suggestionId)
    SGSimpleSettings.shared.dismissedSGSuggestions.append(suggestionId)
}

public func getSGProvidedSuggestions(account: Account) -> Signal<Data?, NoError> {
    let key: PostboxViewKey = .preferences(keys: Set([PreferencesKeys.appConfiguration]))

    return combineLatest(account.postbox.combinedView(keys: [key]), sgDismissedSuggestionsPromise.get())
    |> map { views, dismissedSuggestionsValue -> Data? in
        guard let view = views.views[key] as? PreferencesView,
              let appConfiguration = view.values[PreferencesKeys.appConfiguration]?.get(AppConfiguration.self) else {
            return nil
        }

        func parseAnnouncements(from string: String?) -> [[String: Any]] {
            guard let string = string,
                  let data = string.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data, options: []),
                  let array = json as? [[String: Any]] else {
                return []
            }
            return array
        }

        let ghSuggestions = parseAnnouncements(from: appConfiguration.sgGHSettings.announcementsData)
        let webSuggestions = parseAnnouncements(from: appConfiguration.sgWebSettings.global.announcementsData)
        let combinedSuggestions = ghSuggestions + webSuggestions
        let filteredSuggestions = combinedSuggestions.filter { suggestion in
            guard let id = suggestion["id"] as? String else {
                return true
            }
            return !dismissedSuggestionsValue.contains(id)
                && !SGSimpleSettings.shared.dismissedSGSuggestions.contains(id)
        }

        guard let modifiedData = try? JSONSerialization.data(withJSONObject: filteredSuggestions, options: []) else {
            return nil
        }
        return modifiedData
    }
    |> distinctUntilChanged
}
