import UIKit
import DeviceModel


let DEVICE_MODELS_WITH_APP_BADGE_SUPPORT: [DeviceModel] = [
    .iPhoneX,
    .iPhoneXS,
    .iPhoneXSMax,
    .iPhoneXR,
    .iPhone11,
    .iPhone11Pro,
    .iPhone11ProMax,
    .iPhone12,
    .iPhone12Mini,
    .iPhone12Pro,
    .iPhone12ProMax,
    .iPhone13,
    .iPhone13Mini,
    .iPhone13Pro,
    .iPhone13ProMax,
    .iPhone14,
    .iPhone14Plus,
    .iPhone14Pro,
    .iPhone14ProMax,
    .iPhone15,
    .iPhone15Plus,
    .iPhone15Pro,
    .iPhone15ProMax,
    .iPhone16,
    .iPhone16Plus,
    .iPhone16Pro,
    .iPhone16ProMax,
    .iPhone16e
]

extension DeviceMetrics {

    func sgAppBadgeOffset() -> CGFloat {
        let currentDevice = DeviceModel.current
        var defaultOffset: CGFloat = 0.0
        // https://www.ios-resolution.com/
        // Similar height + Scale
        switch currentDevice {
            case .iPhoneX, .iPhoneXS, .iPhone11Pro, .iPhone12Mini, .iPhone13Mini:
                defaultOffset = 2.0
            case .iPhone11, .iPhoneXR:
                defaultOffset = 6.0
            case .iPhone11ProMax, .iPhoneXSMax:
                defaultOffset = 4.0
            case .iPhone12, .iPhone12Pro, .iPhone13, .iPhone13Pro, .iPhone14, .iPhone16e:
                defaultOffset = 4.0
            case .iPhone12ProMax, .iPhone13ProMax, .iPhone14Plus:
                defaultOffset = 6.0
            case .iPhone14Pro, .iPhone15, .iPhone15Pro, .iPhone16:
                defaultOffset = 18.0
            case .iPhone14ProMax, .iPhone15Plus, .iPhone15ProMax, .iPhone16Plus:
                defaultOffset = 19.0
            case .iPhone16Pro:
                defaultOffset = 21.0
            case .iPhone16ProMax:
                defaultOffset = 22.0
            default:
                defaultOffset = 0.0 // Any device in 2025+ should be like iPhone 14 Pro or better
        }
        let offset: CGFloat = floorToScreenPixels(defaultOffset * self.sgScaleFactor)
        #if DEBUG
        print("deviceMetrics \(self). deviceModel: \(currentDevice). sgIsDisplayZoomed: \(self.sgIsDisplayZoomed). sgScaleFactor: \(self.sgScaleFactor) defaultOffset: \(defaultOffset), offset: \(offset)")
        #endif
        return offset
    }
    
    var sgIsDisplayZoomed: Bool {
        UIScreen.main.scale < UIScreen.main.nativeScale
    }
    
    var sgScaleFactor: CGFloat {
        UIScreen.main.scale / UIScreen.main.nativeScale
    }
    
    var sgShowAppBadge: Bool {
        return DEVICE_MODELS_WITH_APP_BADGE_SUPPORT.contains(DeviceModel.current) // MARK: Swiftgram
    }

}
