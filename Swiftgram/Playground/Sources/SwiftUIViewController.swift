import AsyncDisplayKit
import Display
import Foundation
import SwiftUI
import UIKit
import LegacyUI
import TelegramPresentationData

struct MySwiftUIView: View {
    weak var wrapperController: LegacyController?

    var num: Int64

    var body: some View {
        VStack {
            Text("Hello, World!")
                .font(.title)
                .foregroundColor(.black)

            Spacer(minLength: 0)
            
            Button("Push") {
                self.wrapperController?.push(mySwiftUIViewController(num + 1))
            }.buttonStyle(AppleButtonStyle())
            Spacer()
            Button("Modal") {
                self.wrapperController?.present(mySwiftUIViewController(num + 1), in: .window(.root), with: ViewControllerPresentationArguments(presentationAnimation: .modalSheet))
            }.buttonStyle(AppleButtonStyle())
            Spacer()
            if num > 0 {
                Button("Dismiss") {
                    self.wrapperController?.dismiss()
                }.buttonStyle(AppleButtonStyle())
                Spacer()
            }
        }
//        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.green)
    }
}


struct AppleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .frame(minWidth: 0, maxWidth: .infinity)
            .background(Color.blue)
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

func mySwiftUIViewController(_ num: Int64) -> ViewController {
    let legacyController = LegacyController(presentation: .navigation, theme: defaultPresentationTheme, strings: defaultPresentationStrings)
    legacyController.statusBar.statusBarStyle = defaultPresentationTheme.rootController.statusBarStyle.style
    legacyController.title = "Controller: \(num)"
    
    let swiftUIView = MySwiftUIView(wrapperController: legacyController, num: num)
    let controller = UIHostingController(rootView: swiftUIView)
    legacyController.bind(controller: controller)
    
    return legacyController
}
