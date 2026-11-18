import Foundation
import UIKit
import Display
import UniformTypeIdentifiers
import AccountContext
import PythonPlugins
import JSPlugins

public final class PythonPluginsInstaller {
    private var delegate: PickerDelegate?

    public init() {}

    /// Presents a Files picker filtered to `.js` and `.py` and installs the selection.
    public func present(from context: AccountContext) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.trollPythonScript, .trollJavaScript], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true

        let delegate = PickerDelegate(onPick: { urls in
            for url in urls {
                if url.pathExtension.lowercased() == "js" {
                    _ = JSPluginManager.shared.installPlugin(at: url.path)
                } else {
                    _ = PythonPluginManager.shared.installPlugin(at: url.path)
                }
            }
        })
        picker.delegate = delegate
        self.delegate = delegate

        context.sharedContext.mainWindow?.presentNative(picker)
    }
}

extension UTType {
    /// `public.python-script` is not exposed by every SDK version, so the type
    /// is derived from the file extension instead of hardcoding an identifier.
    public static var trollPythonScript: UTType {
        return UTType(filenameExtension: "py") ?? .plainText
    }
}

extension UTType {
    public static var trollJavaScript: UTType {
        return UTType(filenameExtension: "js") ?? .plainText
    }
}

private final class PickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let onPick: ([URL]) -> Void

    init(onPick: @escaping ([URL]) -> Void) {
        self.onPick = onPick
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.onPick(urls)
    }
}
