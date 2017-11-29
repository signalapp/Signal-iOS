//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import UIKit
import Social

import SignalMessaging
import PureLayout
import SignalServiceKit

class ShareViewController: SLComposeServiceViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // None of the following code is intended to be used, it only serves to prove
        // the project has been configured correctly

        // Proof of cocoapods, utilizes PureLayout
        let someView = UIView()
        someView.backgroundColor = UIColor.green
        view.addSubview(someView)
        someView.autoPinEdgesToSuperviewEdges()
        someView.alpha = 0.2

        let proofOfSharedFramework = StorageCoordinator.shared.path
        let proofOfSSK = textSecureServerURL

        // TODO: Shared Storage via app container
        //let proofOfSharedStorage = TSAccountManager.localNumber()
        let proofOfSharedStorage = "TODO"

        self.placeholder = "shared framework: \(proofOfSharedFramework) \n sharedStorage: \(proofOfSharedStorage) \n proof of ssk: \(proofOfSSK)"
    }

    override func isContentValid() -> Bool {
        // Do validation of contentText and/or NSExtensionContext attachments here
        return true
    }

    override func didSelectPost() {
        // This is called after the user selects Post. Do the upload of contentText and/or NSExtensionContext attachments.

        // Inform the host that we're done, so it un-blocks its UI. Note: Alternatively you could call super's -didSelectPost, which will similarly complete the extension context.
        self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }

    override func configurationItems() -> [Any]! {
        // To add configuration options via table cells at the bottom of the sheet, return an array of SLComposeSheetConfigurationItem here.
        return []
    }

}
