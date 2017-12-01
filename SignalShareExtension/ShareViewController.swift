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

        //        DebugLogger.shared().enableTTYLogging()
        //        if _isDebugAssertConfiguration() {
        //            DebugLogger.shared().enableFileLogging()
        //        } else {
        //            // TODO: Consult OWSPreferences.loggingIsEnabled.
        //            DebugLogger.shared().enableFileLogging()
        //        }

        _ = AppVersion()

        //DDLogWarn(@"%@ application: didFinishLaunchingWithOptions.", self.logTag);
        //
        //// We need to do this _after_ we set up logging but _before_ we do
        //// anything else.
        //[self ensureIsReadyForAppExtensions];
        //
        //#if RELEASE
        //    // ensureIsReadyForAppExtensions may have changed the state of the logging
        //    // preference (due to [NSUserDefaults migrateToSharedUserDefaults]), so honor
        //    // that change if necessary.
        //if (loggingIsEnabled && !OWSPreferences.loggingIsEnabled) {
        //    [DebugLogger.sharedLogger disableFileLogging];
        //}
        //#endif
        //
        //[AppVersion instance];
        //
        //[self startupLogging];

        Logger.debug("\(self.logTag()) \(#function)")
        print("\(self.logTag()) \(#function) \(self.view.frame)")

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

        print("shared framework: \(proofOfSharedFramework) \n sharedStorage: \(proofOfSharedStorage) \n proof of ssk: \(proofOfSSK)")

        Logger.debug("\(self.logTag()) \(#function)")
        print("\(self.logTag()) \(#function) \(self.view.frame)")
    }

    override func viewWillAppear(_ animated: Bool) {
        Logger.debug("\(self.logTag()) \(#function)")
        print("\(self.logTag()) \(#function) \(self.view.frame)")

        super.viewWillAppear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        Logger.debug("\(self.logTag()) \(#function)")
        print("\(self.logTag()) \(#function) \(self.view.frame)")

        super.viewDidAppear(animated)
    }

    // MARK: SAELoadViewDelegate

    public func shareExtensionWasCancelled() {
        self.extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }
}
