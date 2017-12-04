//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

import UIKit

import SignalMessaging
import PureLayout
import SignalServiceKit

class ShareViewController: UINavigationController, SAELoadViewDelegate {

    override func loadView() {
        super.loadView()

        // This should be the first thing we do.
        SetCurrentAppContext(ShareAppExtensionContext())

        DebugLogger.shared().enableTTYLogging()
        if _isDebugAssertConfiguration() {
            DebugLogger.shared().enableFileLogging()
        } else if (OWSPreferences.isLoggingEnabled()) {
            // TODO: Consult OWSPreferences.isLoggingEnabled.
            DebugLogger.shared().enableFileLogging()
        }

        _ = AppVersion()

        //[self startupLogging];

        Logger.debug("\(self.logTag()) \(#function)")

        let loadViewController = SAELoadViewController(delegate:self)
        self.pushViewController(loadViewController, animated: false)
        self.isNavigationBarHidden = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let proofOfSharedFramework = StorageCoordinator.shared.path
        let proofOfSSK = textSecureServerURL

        // TODO: Shared Storage via app container
        //let proofOfSharedStorage = TSAccountManager.localNumber()
        let proofOfSharedStorage = "TODO"

        Logger.debug("shared framework: \(proofOfSharedFramework) \n sharedStorage: \(proofOfSharedStorage) \n proof of ssk: \(proofOfSSK)")

        Logger.debug("\(self.logTag()) \(#function)")
    }

    override func viewWillAppear(_ animated: Bool) {
        Logger.debug("\(self.logTag()) \(#function)")

        super.viewWillAppear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        Logger.debug("\(self.logTag()) \(#function)")

        super.viewDidAppear(animated)
    }

    // MARK: SAELoadViewDelegate

    public func shareExtensionWasCancelled() {
        self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }
}
