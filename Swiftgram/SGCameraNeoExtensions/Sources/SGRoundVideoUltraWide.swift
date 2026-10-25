import Foundation
import AVFoundation
import CoreGraphics

// The back camera for round videos is the virtual device that has the ultra-wide constituent, so a pinch can zoom out
// to 0.5x. Its videoZoomFactor 1.0 is the ultra-wide lens; the wide lens (1x on screen) starts at the switch-over factor.
func sgRoundVideoVirtualBackDevice(requiresMultiCam: Bool, mode: NeoCameraImpl.RoundVideoMode) -> AVCaptureDevice? {
    guard #available(iOS 13.0, *) else {
        return nil
    }
    let deviceTypes: [AVCaptureDevice.DeviceType] = [
        .builtInTripleCamera,
        .builtInDualWideCamera
    ]
    for deviceType in deviceTypes {
        guard let device = AVCaptureDevice.default(deviceType, for: .video, position: .back), sgIsUltraWideVirtualDevice(device) else {
            continue
        }
        if requiresMultiCam && !sgSupportsMultiCam(backDevice: device) {
            continue
        }
        if roundVideoCaptureFormat(for: device, requiresMultiCam: requiresMultiCam, mode: mode) != nil {
            return device
        }
    }
    return nil
}

// A multi-cam session runs only device combinations the system lists; any other pair raises when added.
@available(iOS 13.0, *)
private func sgSupportsMultiCam(backDevice: AVCaptureDevice) -> Bool {
    guard AVCaptureMultiCamSession.isMultiCamSupported else {
        return false
    }
    // The front camera CameraNeo.makeVideoDevice(position: .front) picks.
    guard let frontDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) ?? AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInTrueDepthCamera], mediaType: .video, position: .front).devices.first else {
        return false
    }
    let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [backDevice.deviceType, frontDevice.deviceType], mediaType: .video, position: .unspecified)
    return discoverySession.supportedMultiCamDeviceSets.contains(where: { deviceSet in
        return deviceSet.contains(where: { $0.uniqueID == backDevice.uniqueID }) && deviceSet.contains(where: { $0.uniqueID == frontDevice.uniqueID })
    })
}

func sgIsUltraWideVirtualDevice(_ device: AVCaptureDevice) -> Bool {
    guard #available(iOS 13.0, *) else {
        return false
    }
    return device.position == .back && device.isVirtualDevice && !device.virtualDeviceSwitchOverVideoZoomFactors.isEmpty && device.constituentDevices.contains(where: { $0.deviceType == .builtInUltraWideCamera })
}

// The videoZoomFactor that shows the wide lens: 1.0 for a physical camera.
func sgNeutralZoomFactor(_ device: AVCaptureDevice) -> CGFloat {
    if #available(iOS 13.0, *), sgIsUltraWideVirtualDevice(device) {
        if let indexOfWideAngle = device.constituentDevices.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }), indexOfWideAngle > 0, indexOfWideAngle - 1 < device.virtualDeviceSwitchOverVideoZoomFactors.count {
            return CGFloat(device.virtualDeviceSwitchOverVideoZoomFactors[indexOfWideAngle - 1].doubleValue)
        }
    }
    return 1.0
}

// Call with the device locked, after its activeFormat is set: a new format leaves the zoom at the ultra-wide lens.
func sgConfigureRoundVideoVirtualDevice(_ device: AVCaptureDevice) {
    guard sgIsUltraWideVirtualDevice(device) else {
        return
    }
    if #available(iOS 15.0, *), device.activePrimaryConstituentDeviceSwitchingBehavior != .unsupported {
        device.setPrimaryConstituentDeviceSwitchingBehavior(.auto, restrictedSwitchingBehaviorConditions: [])
    }
    let neutralZoomFactor = sgNeutralZoomFactor(device)
    device.videoZoomFactor = min(max(neutralZoomFactor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
}
