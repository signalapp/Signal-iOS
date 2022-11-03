//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

/// Any view controller which wants to be able cancel back button
/// presses and back gestures should implement this protocol.
public protocol OWSNavigationView: AnyObject {

    /// Will be called if the back button was pressed or if a back gesture
    /// was performed but not if the view is popped programmatically.
    func shouldCancelNavigationBack() -> Bool
}

/// This navigation controller subclass should be used anywhere we might
/// want to cancel back button presses or back gestures due to, for example,
/// unsaved changes.
@objc
open class OWSNavigationController: OWSNavigationControllerBase {

    /// If set, this property lets us override prefersStatusBarHidden behavior.
    /// This is useful for suppressing the status bar while a modal is presented,
    /// regardless of which view is currently visible.
    public var ows_prefersStatusBarHidden: Bool = false

    /// This is the property to use when the whole navigation stack
    /// needs to have status bar in a fixed style, e.g. when presenting
    /// a view controller modally in a fixed dark or light style.
    public var ows_preferredStatusBarStyle: UIStatusBarStyle?

    public override var prefersStatusBarHidden: Bool {
        if ows_prefersStatusBarHidden {
            return true
        }
        return super.prefersStatusBarHidden
    }

    public init() {
        super.init(navigationBarClass: OWSNavigationBar.self, toolbarClass: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .ThemeDidChange,
            object: nil
        )
    }

    public override convenience init(rootViewController: UIViewController) {
        self.init()
        self.pushViewController(rootViewController, animated: false)
    }

    @available(*, unavailable)
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var preferredStatusBarStyle: UIStatusBarStyle {
        if let ows_preferredStatusBarStyle = ows_preferredStatusBarStyle {
            return ows_preferredStatusBarStyle
        }
        if !CurrentAppContext().isMainApp {
            return super.preferredStatusBarStyle
        } else if
            let presentedViewController = self.presentedViewController,
            !presentedViewController.isBeingDismissed
        {
            return presentedViewController.preferredStatusBarStyle
        } else if #available(iOS 13, *) {
            return Theme.isDarkThemeEnabled ? .lightContent : .darkContent
        } else {
            return Theme.isDarkThemeEnabled ? .lightContent : super.preferredStatusBarStyle
        }
    }

    open override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if let delegateOrientations = self.delegate?.navigationControllerSupportedInterfaceOrientations?(self) {
            return delegateOrientations
        } else if let visibleViewController = self.visibleViewController {
            return visibleViewController.supportedInterfaceOrientations
        } else {
            return UIDevice.current.defaultSupportedOrientations
        }
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        interactivePopGestureRecognizer?.delegate = self
    }

    @objc
    private func themeDidChange() {
        navigationBar.barTintColor = UINavigationBar.appearance().barTintColor
        navigationBar.tintColor = UINavigationBar.appearance().tintColor
        navigationBar.titleTextAttributes = UINavigationBar.appearance().titleTextAttributes
    }
}

extension OWSNavigationController: UIGestureRecognizerDelegate {

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        owsAssertDebug(gestureRecognizer === self.interactivePopGestureRecognizer)

        if let navigationView = topViewController as? OWSNavigationView {
            return !navigationView.shouldCancelNavigationBack()
        } else {
            return topViewController != viewControllers.first
        }
    }
}

extension OWSNavigationController: UINavigationBarDelegate {

    // All OWSNavigationController serve as the UINavigationBarDelegate for their navbar.
    // We override shouldPopItem: in order to cancel some back button presses - for example,
    // if a view has unsaved changes.
    public func navigationBar(_ navigationBar: UINavigationBar, shouldPop item: UINavigationItem) -> Bool {
        owsAssertDebug(interactivePopGestureRecognizer?.delegate === self)

        // wasBackButtonClicked is true if the back button was pressed but not
        // if a back gesture was performed or if the view is popped programmatically.
        let wasBackButtonClicked = topViewController?.navigationItem == item
        var result = true
        if wasBackButtonClicked {
            if let navView = topViewController as? OWSNavigationView {
                result = !navView.shouldCancelNavigationBack()
            }
        }

        // If we're not going to cancel the pop/back, we need to call the super
        // implementation since it has important side effects.
        if result {
            // NOTE: result might end up false if the super implementation cancels the
            // the pop/back.
            super.ows_navigationBar(navigationBar, shouldPop: item)
            result = true
        }

        return result
    }
}
