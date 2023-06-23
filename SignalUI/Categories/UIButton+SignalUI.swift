//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

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

// MARK: -

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
}

// MARK: -

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
