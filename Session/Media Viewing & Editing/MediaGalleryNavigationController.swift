// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SignalUtilitiesKit
import SessionUIKit

class MediaGalleryNavigationController: OWSNavigationController {
    // HACK: Though we don't have an input accessory view, the VC we are presented above (ConversationVC) does.
    // If the app is backgrounded and then foregrounded, when OWSWindowManager calls mainWindow.makeKeyAndVisible
    // the ConversationVC's inputAccessoryView will appear *above* us unless we'd previously become first responder.
    override public var canBecomeFirstResponder: Bool {
        return true
    }
    
    // MARK: - UI
    
    private lazy var backgroundView: UIView = {
        let result: UIView = UIView()
        result.themeBackgroundColor = .backgroundSecondary
        
        return result
    }()

    // MARK: - View Lifecycle

    override var preferredStatusBarStyle: UIStatusBarStyle { return ThemeManager.currentTheme.statusBarStyle }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.themeBackgroundColor = .backgroundSecondary
        
        // Insert a view to ensure the nav bar colour goes to the top of the screen
        relayoutBackgroundView()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // If the user's device is already rotated, try to respect that by rotating to landscape now
        UIViewController.attemptRotationToDeviceOrientation()
    }

    // MARK: - Orientation

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .allButUpsideDown
    }
    
    // MARK: - Functions
    
    private func relayoutBackgroundView() {
        guard !backgroundView.isHidden else {
            backgroundView.removeFromSuperview()
            return
        }
        
        view.insertSubview(backgroundView, belowSubview: navigationBar)

        backgroundView.pin(.top, to: .top, of: view)
        backgroundView.pin(.left, to: .left, of: navigationBar)
        backgroundView.pin(.right, to: .right, of: navigationBar)
        backgroundView.pin(.bottom, to: .bottom, of: navigationBar)
    }
    
    override func setNavigationBarHidden(_ hidden: Bool, animated: Bool) {
        super.setNavigationBarHidden(hidden, animated: animated)
        
        backgroundView.isHidden = hidden
        relayoutBackgroundView()
    }
}
