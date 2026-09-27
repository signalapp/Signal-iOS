//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

// MARK: - SheetNavigationController

/// A native sheet containing a navigation stack of
/// ``NavStackSheetViewController``s, sized to the top view controller's content.
open class SheetNavigationController: UINavigationController {
    open var sheetBackgroundColor: UIColor { UIColor.Signal.groupedBackground }

    public init(rootViewController: NavStackSheetViewController) {
        // `init(rootViewController:)` calls `viewDidLoad` too
        // soon for the sheet to be properly initialized.
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
        viewControllers = [rootViewController]
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
        if #unavailable(iOS 26) {
            view.backgroundColor = sheetBackgroundColor
        }
        sheetPresentationController?.setUpContentSizedDetent { [weak self] in
            guard let topViewController = self?.topViewController else { return nil }
            guard let sheet = topViewController as? NavStackSheetViewController else {
                owsFailDebug("SheetNavigationController requires NavStackSheetViewController content")
                return nil
            }
            return sheet.customSheetHeight()
        }
    }

    override open func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        // The presentation jumps if you try to set the height here,
        // pre-iOS 26 jumps if you don't set it here 🤷‍♀️
        if #unavailable(iOS 26) {
            sheetPresentationController?.reloadContentSizedHeight(animated: false)
        }
    }

    override open func accessibilityPerformEscape() -> Bool {
        if viewControllers.count > 1 {
            popViewController(animated: true)
            return true
        }
        if presentingViewController != nil {
            dismiss(animated: true)
            return true
        }
        return super.accessibilityPerformEscape()
    }

    /// Push with a fade to make the animations less jarring with a simultaneous sheet size change
    public func pushViewControllerWithFade(_ viewController: NavStackSheetViewController) {
        addFadeTransition()
        pushViewController(viewController, animated: false)
        reloadSheetHeightForNavigation()
    }

    /// Pop with a fade to make the animations less jarring with a simultaneous sheet size change
    @discardableResult
    public func popViewControllerWithFade() -> UIViewController? {
        addFadeTransition()
        defer { reloadSheetHeightForNavigation() }
        return popViewController(animated: false)
    }

    private func reloadSheetHeightForNavigation() {
        view.layoutIfNeeded()
        sheetPresentationController?.reloadContentSizedHeight(animated: true)
    }

    private func addFadeTransition() {
        let transition = CATransition()
        transition.duration = 0.3
        transition.type = .fade
        transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        view.layer.add(transition, forKey: nil)
    }
}

// MARK: - UISheetPresentationController + content-sized detent

extension UISheetPresentationController {
    func setUpContentSizedDetent(height: @escaping @MainActor () -> CGFloat?) {
        guard #available(iOS 16, *) else {
            detents = [.medium(), .large()]
            return
        }
        detents = [.custom { [weak self] context in
            guard let self else { return context.maximumDetentValue }
            let presentedView: UIView = presentedViewController.view

            // Only do the below force-resizing before the view joins the
            // hierarchy as UIKit will call this again during window resizing,
            // resulting in a crash.
            if presentedView.superview == nil {
                // We can't measure the height until we have the sheet's width
                let sheetWidth = frameOfPresentedViewInContainerView.width
                if sheetWidth > 0, sheetWidth != presentedView.frame.size.width {
                    presentedView.frame.size.width = sheetWidth
                }
                presentedView.layoutIfNeeded()
            }
            let height = height() ?? context.maximumDetentValue
            return max(0, min(height, context.maximumDetentValue))
        }]
    }

    func reloadContentSizedHeight(animated: Bool) {
        guard #available(iOS 16, *) else { return }
        guard animated else {
            invalidateDetents()
            return
        }
        animateChanges {
            invalidateDetents()
        }
    }
}

// MARK: - ContentSizedSheetHeightReloader

@MainActor
final class ContentSizedSheetHeightReloader {
    private weak var viewController: OWSViewController?
    private var isReloadScheduled = false

    init(viewController: OWSViewController) {
        self.viewController = viewController
    }

    func reload() {
        guard let viewController else { return }
        guard viewController.lifecycle == .appeared else {
            viewController.sheetPresentationController?.reloadContentSizedHeight(animated: false)
            return
        }
        guard !isReloadScheduled else { return }
        isReloadScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isReloadScheduled = false
            self.viewController?.sheetPresentationController?.reloadContentSizedHeight(animated: true)
        }
    }
}
