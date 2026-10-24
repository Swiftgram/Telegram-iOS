// import UIKit
// import MobileCoreServices
// import UrlEscaping

// @objc(SGActionRequestHandler)
// class SGActionRequestHandler: NSObject, NSExtensionRequestHandling {
//     var extensionContext: NSExtensionContext?
    
//     func beginRequest(with context: NSExtensionContext) {
//         // Do not call super in an Action extension with no user interface
//         self.extensionContext = context
              
//         let itemProvider = context.inputItems
//             .compactMap({ $0 as? NSExtensionItem })
//             .reduce([NSItemProvider](), { partialResult, acc in
//                 var nextResult = partialResult
//                 nextResult += acc.attachments ?? []
//                 return nextResult
//             })
//             .filter({ $0.hasItemConformingToTypeIdentifier(kUTTypePropertyList as String) })
//             .first
        
//         guard let itemProvider = itemProvider else {
//             return doneWithInvalidLink()
//         }
        
//         itemProvider.loadItem(forTypeIdentifier: kUTTypePropertyList as String, options: nil, completionHandler: { [weak self] item, error in
//             DispatchQueue.main.async {
//                 guard
//                     let dictionary = item as? NSDictionary,
//                     let results = dictionary[NSExtensionJavaScriptPreprocessingResultsKey] as? NSDictionary
//                 else {
//                     self?.doneWithInvalidLink()
//                     return
//                 }
                
//                 if let url = results["url"] as? String, let escapedUrl = url.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) {
//                     self?.doneWithResults(["openURL": "sg://parseurl?url=\(escapedUrl)"])
//                 } else {
//                     self?.doneWithInvalidLink()
//                 }
//             }
//         })
//     }

//     func doneWithInvalidLink() {
//         doneWithResults(["alert": "Invalid link"])
//     }
    
//     func doneWithResults(_ resultsForJavaScriptFinalizeArg: [String: Any]?) {
//         if let resultsForJavaScriptFinalize = resultsForJavaScriptFinalizeArg {
//             let resultsDictionary = [NSExtensionJavaScriptFinalizeArgumentKey: resultsForJavaScriptFinalize]
//             let resultsProvider = NSItemProvider(item: resultsDictionary as NSDictionary, typeIdentifier: kUTTypePropertyList as String)
//             let resultsItem = NSExtensionItem()
//             resultsItem.attachments = [resultsProvider]
//             self.extensionContext!.completeRequest(returningItems: [resultsItem], completionHandler: nil)
//         } else {
//             self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
//         }
//         self.extensionContext = nil
//     }
// }
