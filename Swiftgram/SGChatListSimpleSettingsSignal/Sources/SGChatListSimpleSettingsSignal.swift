import SGSimpleSettings
import Foundation
import SwiftSignalKit

public func sgSimpleSettingsBoolSignal(_ key: SGSimpleSettings.Keys, defaultValue: Bool) -> Signal<Bool, NoError> {
    let initial = Signal<Bool, NoError>.single(UserDefaults.standard.object(forKey: key.rawValue) as? Bool ?? defaultValue)
    let changes = Signal<Bool, NoError> { subscriber in
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: nil
        ) { _ in
            let value = UserDefaults.standard.object(forKey: key.rawValue) as? Bool ?? defaultValue
            subscriber.putNext(value)
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    return (initial |> then(changes)) |> distinctUntilChanged
}

/// Fires when one of the settings changes, not on subscribing. UserDefaults reports only that something
/// changed, so the values are compared.
public func sgSimpleSettingsChangesSignal(_ keys: [SGSimpleSettings.Keys]) -> Signal<Void, NoError> {
    return Signal { subscriber in
        let currentValues: () -> [NSObject?] = {
            return keys.map { UserDefaults.standard.object(forKey: $0.rawValue) as? NSObject }
        }
        let previousValues = Atomic<[NSObject?]>(value: currentValues())
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: nil
        ) { _ in
            let values = currentValues()
            if previousValues.swap(values) != values {
                subscriber.putNext(Void())
            }
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
