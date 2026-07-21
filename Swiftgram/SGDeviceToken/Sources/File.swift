import SwiftSignalKit
import DeviceCheck

public enum SGDeviceTokenError {
    case unsupportedDevice
    case generic(String)
}

public func getDeviceToken() -> Signal<String, SGDeviceTokenError> {
    return Signal { subscriber in
        let currentDevice = DCDevice.current
        if currentDevice.isSupported {
            currentDevice.generateToken { (data, error) in
                guard error == nil else {
                    subscriber.putError(.generic(error!.localizedDescription))
                    return
                }
                if let tokenData = data {
                    subscriber.putNext(tokenData.base64EncodedString())
                    subscriber.putCompletion()
                } else {
                    subscriber.putError(.generic("Empty Token"))
                }
            }
        } else {
            subscriber.putError(.unsupportedDevice)
        }
        return ActionDisposable {
        }
    }
}
