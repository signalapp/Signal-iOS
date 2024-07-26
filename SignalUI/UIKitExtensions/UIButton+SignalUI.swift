//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

// MARK: - UIButton

public extension UIButton {
    /// Add spacing between a button's image and its title.
    ///
    /// Modified from [this project][0], licensed under the MIT License.
    ///
    /// [0]: https://github.com/noahsark769/NGUIButtonInsetsExample
    func setPaddingBetweenImageAndText(to padding: CGFloat, isRightToLeft: Bool) {
        if isRightToLeft {
            ows_contentEdgeInsets = .init(
                top: ows_contentEdgeInsets.top,
                left: padding,
                bottom: ows_contentEdgeInsets.bottom,
                right: ows_contentEdgeInsets.right
            )
            ows_titleEdgeInsets = .init(
                top: ows_titleEdgeInsets.top,
                left: -padding,
                bottom: ows_titleEdgeInsets.bottom,
                right: padding
            )
        } else {
            ows_contentEdgeInsets = .init(
                top: ows_contentEdgeInsets.top,
                left: ows_contentEdgeInsets.left,
                bottom: ows_contentEdgeInsets.bottom,
                right: padding
            )
            ows_titleEdgeInsets = .init(
                top: ows_titleEdgeInsets.top,
                left: padding,
                bottom: ows_titleEdgeInsets.bottom,
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

// MARK: - UIButton.Configuration

extension UIConfigurationTextAttributesTransformer {
    /// Assign to a text attributes transformer (e.g., `UIButton.Configuration.titleTextAttributesTransformer`)
    /// to configure a default font for that configuration.
    ///
    /// This differs from setting the `AttributedText` directly in that a
    /// `.font` attribute set directly on the attributed text will take
    /// precedence over the default font.
    public static func defaultFont(_ defaultFont: UIFont) -> UIConfigurationTextAttributesTransformer {
        UIConfigurationTextAttributesTransformer { attributes in
            guard attributes.font == nil else { return attributes }
            var attributes = attributes
            attributes.font = defaultFont
            return attributes
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

        convenience init(
            title: String,
            style: UIBarButtonItem.Style,
            action: @escaping () -> Void
        ) {
            let handler = Handler(actionClosure: action)
            self.init(title: title, style: style, target: handler, action: #selector(handler.action))
            self.handler = handler
        }

        convenience init(
            image: UIImage,
            style: UIBarButtonItem.Style,
            action: @escaping () -> Void
        ) {
            let handler = Handler(actionClosure: action)
            self.init(image: image, style: style, target: handler, action: #selector(handler.action))
            self.handler = handler
        }
    }

    /// Creates a bar button with the given title that performs the action in the provided closure.
    static func button(
        title: String,
        style: UIBarButtonItem.Style,
        action: @escaping () -> Void
    ) -> UIBarButtonItem {
        ClosureBarButtonItem(title: title, style: style, action: action)
    }

    /// Creates a bar button with the given icon that performs the action in the provided closure.
    static func button(
        icon: ThemeIcon,
        style: UIBarButtonItem.Style,
        action: @escaping () -> Void
    ) -> UIBarButtonItem {
        ClosureBarButtonItem(image: Theme.iconImage(icon), style: style, action: action)
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
        dismissingFrom viewController: UIViewController?,
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
        dismissingFrom viewController: UIViewController?,
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

    /// Creates a "Done" bar button which dismisses the view using the provided view controller.
    /// - Parameters:
    ///   - viewController: The view controller to dismiss from.
    ///   - animated: Whether to animate the dismiss.
    ///   - completion: The block to execute after the view controller is dismissed.
    /// - Returns: A new `UIBarButtonItem`.
    static func doneButton(
        dismissingFrom viewController: UIViewController?,
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) -> UIBarButtonItem {
        Self.doneButton { [weak viewController] in
            viewController?.dismiss(animated: animated, completion: completion)
        }
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
