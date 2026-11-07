import SafariServices

public class SFSafariViewControllerPlusDidFinish: SFSafariViewController, SFSafariViewControllerDelegate {
    public var onDidFinish: (() -> Void)?

    public override init(url URL: URL, configuration: SFSafariViewController.Configuration = SFSafariViewController.Configuration()) {
        super.init(url: URL, configuration: configuration)
        self.delegate = self
    }

    public func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        onDidFinish?()
    }
}
