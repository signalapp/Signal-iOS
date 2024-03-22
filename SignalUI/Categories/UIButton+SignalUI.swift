//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

// MARK: - UIButton

public extension UIButton {
    /// Add spacing between a button's image and its title.
    ///
    /// Modified from [this project][0], licensed under the MIT License.
    ///
    /// [0]: https://github.com/noahsark769/NGUIButtonInsetsExample
    func setPaddingBetweenImageAndText(to padding: CGFloat, isRightToLeft: Bool) {
        if isRightToLeft {
            contentEdgeInsets = .init(
                top: contentEdgeInsets.top,
                left: padding,
                bottom: contentEdgeInsets.bottom,
                right: contentEdgeInsets.right
            )
            titleEdgeInsets = .init(
                top: titleEdgeInsets.top,
                left: -padding,
                bottom: titleEdgeInsets.bottom,
                right: padding
            )
        } else {
            contentEdgeInsets = .init(
                top: contentEdgeInsets.top,
                left: contentEdgeInsets.left,
                bottom: contentEdgeInsets.bottom,
                right: padding
            )
            titleEdgeInsets = .init(
                top: titleEdgeInsets.top,
                left: padding,
                bottom: titleEdgeInsets.bottom,
                right: -padding
            )
        }
    }

    func setTemplateImage(_ templateImage: UIImage?, tintColor: UIColor) {
        guard let templateImage else {
            owsFailDebug("Missing image")
            return
        }
        setImage(templateImage.withRenderingMode(.alwaysTemplate), for: .normal)
        self.tintColor = tintColor
    }

    func setTemplateImageName(_ imageName: String, tintColor: UIColor) {
        guard let image = UIImage(named: imageName) else {
            owsFailDebug("Couldn't load image: \(imageName)")
            return
        }
        setTemplateImage(image, tintColor: tintColor)
    }

    class func withTemplateImage(_ templateImage: UIImage?, tintColor: UIColor) -> UIButton {
        let button = UIButton()
        button.setTemplateImage(templateImage, tintColor: tintColor)
        return button
    }

    class func withTemplateImageName(_ imageName: String, tintColor: UIColor) -> UIButton {
        let button = UIButton()
        button.setTemplateImageName(imageName, tintColor: tintColor)
        return button
    }

    func setImage(_ image: UIImage?, animated: Bool) {
        setImage(image, withAnimationDuration: animated ? 0.2 : 0)
    }

    func setImage(_ image: UIImage?, withAnimationDuration duration: TimeInterval) {
        guard duration > 0 else {
            setImage(image, for: .normal)
            return
        }
        UIView.transition(with: self, duration: duration, options: .transitionCrossDissolve) {
            self.setImage(image, for: .normal)
        }
    }
}

// MARK: - UIBarButtonItem

public extension UIBarButtonItem {

    convenience init(
        image: UIImage?,
        style: UIBarButtonItem.Style,
        target: Any?,
        action: Selector?,
        accessibilityIdentifier: String
    ) {
        self.init(image: image, style: style, target: target, action: action)
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    convenience init(
        image: UIImage?,
        landscapeImagePhone: UIImage?,
        style: UIBarButtonItem.Style,
        target: Any?,
        action: Selector?,
        accessibilityIdentifier: String
    ) {
        self.init(image: image, landscapeImagePhone: landscapeImagePhone, style: style, target: target, action: action)
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    convenience init(
        title: String?,
        style: UIBarButtonItem.Style,
        target: Any?,
        action: Selector?,
        accessibilityIdentifier: String
    ) {
        self.init(title: title, style: style, target: target, action: action)
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    convenience init(
        barButtonSystemItem systemItem: UIBarButtonItem.SystemItem,
        target: Any?,
        action: Selector?,
        accessibilityIdentifier: String
    ) {
        self.init(barButtonSystemItem: systemItem, target: target, action: action)
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    convenience init(customView: UIView, accessibilityIdentifier: String) {
        self.init(customView: customView)
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    private class ClosureBarButtonItem: UIBarButtonItem {
        private class Handler {
            var actionClosure: () -> Void
            init(actionClosure: @escaping () -> Void) {
                self.actionClosure = actionClosure
            }
            @objc
            func action() {
                actionClosure()
            }
        }

        private var handler: Handler?

        convenience init(
            systemItem: UIBarButtonItem.SystemItem,
            action: @escaping () -> Void
        ) {
            let handler = Handler(actionClosure: action)
            // The `Handler` type exists because we can't
            // reference `self` in its own initializer call.
            self.init(barButtonSystemItem: systemItem, target: handler, action: #selector(handler.action))
            // Keep a strong reference to the Handler
            self.handler = handler
        }
    }

    // Keep this static function public instead of exposing ClosureBarButtonItem
    // because ClosureBarButtonItem will only function properly if using its
    // custom convenience initializer.
    /// Creates a system bar button item which performs the action in the provided closure.
    ///
    /// - Parameters:
    ///   - systemItem: The system item to use.
    ///   - action: The action to perform on tap.
    /// - Returns: A new `UIBarButtonItem`.
    static func systemItem(
        _ systemItem: UIBarButtonItem.SystemItem,
        action: @escaping () -> Void
    ) -> UIBarButtonItem {
        ClosureBarButtonItem(systemItem: systemItem, action: action)
    }

    /// Creates a "Cancel" bar button which performs the action in the provided closure.
    static func cancelButton(action: @escaping () -> Void) -> UIBarButtonItem {
        Self.systemItem(.cancel, action: action)
    }

    /// Creates a "Cancel" bar button which dismisses the view using the provided view controller.
    /// - Parameters:
    ///   - viewController: The view controller to dismiss from.
    ///   - animated: Whether to animate the dismiss.
    ///   - completion: The block to execute after the view controller is dismissed.
    /// - Returns: A new `UIBarButtonItem`.
    static func cancelButton(
        dismissingFrom viewController: UIViewController,
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) -> UIBarButtonItem {
        Self.cancelButton { [weak viewController] in
            viewController?.dismiss(animated: animated, completion: completion)
        }
    }

    /// Creates a "Cancel" bar button which dismisses the view after checking if
    /// there are unsaved changes and presenting a confirmation sheet if so.
    /// - Parameters:
    ///   - viewController: The view controller to display the confirmation and to dismiss from.
    ///   - hasUnsavedChanges: A closure called on tap to check if there are
    ///   unsaved changes. Returning `nil` is equivalent to returning `false`.
    ///   - animated: Whether to animate the dismiss.
    ///   - completion: The block to execute after the view controller is dismissed.
    /// - Returns: A new `UIBarButtonItem`.
    static func cancelButton(
        dismissingFrom viewController: UIViewController,
        hasUnsavedChanges: @escaping () -> Bool?,
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) -> UIBarButtonItem {
        Self.cancelButton { [weak viewController] in
            if hasUnsavedChanges() == true {
                OWSActionSheets.showPendingChangesActionSheet(discardAction: { [weak viewController] in
                    viewController?.dismiss(animated: animated, completion: completion)
                })
            } else {
                viewController?.dismiss(animated: animated, completion: completion)
            }
        }
    }

    /// Creates a "Cancel" bar button which pops the view controller using the provided navigation controller.
    /// - Parameters:
    ///   - navigationController: The navigation controller to pop.
    ///   - animated: Whether to animate the pop.
    /// - Returns: A new `UIBarButtonItem`.
    static func cancelButton(
        poppingFrom navigationController: UINavigationController?,
        animated: Bool = true
    ) -> UIBarButtonItem {
        Self.cancelButton { [weak navigationController] in
            navigationController?.popViewController(animated: animated)
        }
    }

    /// Creates a "Done" bar button which performs the action in the provided closure.
    static func doneButton(action: @escaping () -> Void) -> UIBarButtonItem {
        Self.systemItem(.done, action: action)
    }

    // Feel free to add more system item functions as the need arises
}

// MARK: - UIToolbar

public extension UIToolbar {

    static func clear() -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.backgroundColor = .clear

        // Making a toolbar transparent requires setting an empty uiimage
        toolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)

        // hide 1px top-border
        toolbar.clipsToBounds = true

        return toolbar
    }
}
