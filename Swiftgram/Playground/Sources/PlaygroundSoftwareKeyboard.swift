import UIKit

/// Test-fixture setup only. Simulator can report an offscreen Keyboard accessibility element while
/// a hardware keyboard suppresses the software keyboard. Match NativeNavigationReference's local
/// setup, without changing persistent keyboard preferences or the production SwiftUI adapter.
func playgroundEnsureSoftwareKeyboard() {
    #if targetEnvironment(simulator)
    guard ProcessInfo.processInfo.arguments.contains("--force-software-keyboard"),
          let keyboardClass = NSClassFromString("UIKeyboardImpl") as? NSObject.Type,
          let keyboard = keyboardClass.perform(NSSelectorFromString("activeInstance"))?.takeUnretainedValue() as? NSObject else {
        return
    }
    let selector = NSSelectorFromString("setInHardwareKeyboardMode:shouldMoveKeyboard:")
    guard let method = class_getInstanceMethod(type(of: keyboard), selector) else { return }
    typealias SetHardwareMode = @convention(c) (NSObject, Selector, Bool, Bool) -> Void
    unsafeBitCast(method_getImplementation(method), to: SetHardwareMode.self)(keyboard, selector, false, true)
    let showSelector = NSSelectorFromString("showKeyboard")
    if keyboard.responds(to: showSelector) { _ = keyboard.perform(showSelector) }
    #endif
}
