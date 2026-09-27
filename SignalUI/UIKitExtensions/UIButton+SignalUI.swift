//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

// MARK: - NSDirectionalEdgeInsets

private extension NSDirectionalEdgeInsets {
    static var largeButtonContentInsets: NSDirectionalEdgeInsets {
        NSDirectionalEdgeInsets(hMargin: 16, vMargin: 15)
    }

    static var mediumButtonContentInsets: NSDirectionalEdgeInsets {
        NSDirectionalEdgeInsets(hMargin: 16, vMargin: 12)
    }

    static var smallButtonContentInsets: NSDirectionalEdgeInsets {
        NSDirectionalEdgeInsets(hMargin: 12, vMargin: 8)
    }

}

// MARK: - UIButton

public extension UIButton {
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

    func enableMultilineLabel() {
        guard let titleLabel else { return }

        configuration?.titleAlignment = .center
        configuration?.titleLineBreakMode = .byWordWrapping

        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center

        configurationUpdateHandler = { button in
            button.titleLabel?.numberOfLines = 0
            button.titleLabel?.lineBreakMode = .byWordWrapping
        }
    }

    func enclosedInVerticalStackView(isFullWidthButton: Bool) -> UIStackView {
        return [self].enclosedInVerticalStackView(isFullWidthButtons: isFullWidthButton)
    }
}

public extension Array where Element == UIButton {

    func enclosedInVerticalStackView(isFullWidthButtons: Bool) -> UIStackView {
        return UIStackView.verticalButtonStack(buttons: self, isFullWidthButtons: isFullWidthButtons)
    }
}

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

public extension UIButton.Configuration {

    private mutating func applyCorners() {
        if #available(iOS 26, *) {
            cornerStyle = .capsule
            return
        }
        cornerStyle = .fixed
        background.cornerRadius = 14
    }

    private static func basePrimary() -> Self {
        var configuration: UIButton.Configuration
        if #available(iOS 26, *) {
            configuration = .prominentGlass()
        } else {
            configuration = .borderedProminent()
        }
        configuration.titleAlignment = .center
        configuration.titleTextAttributesTransformer = .defaultFont(.dynamicTypeHeadlineClamped)
        configuration.baseBackgroundColor = .Signal.accent
        configuration.applyCorners()
        return configuration
    }

    private static func baseSecondary() -> Self {
        var configuration: UIButton.Configuration
        if #available(iOS 26, *) {
            configuration = .prominentGlass()
            configuration.baseForegroundColor = .Signal.label
        } else {
            configuration = .plain()
            configuration.baseForegroundColor = .Signal.accent
        }
        configuration.titleAlignment = .center
        configuration.titleTextAttributesTransformer = .defaultFont(.dynamicTypeHeadlineClamped)
        configuration.baseBackgroundColor = .clear
        configuration.applyCorners()
        return configuration
    }

    static func largePrimary(title: String) -> Self {
        var configuration = basePrimary()
        configuration.title = title
        configuration.contentInsets = .largeButtonContentInsets
        return configuration
    }

    static func largeSecondary(title: String) -> Self {
        var configuration = baseSecondary()
        configuration.title = title
        configuration.contentInsets = .largeButtonContentInsets
        if #unavailable(iOS 26) {
            // Smaller height when button doesn't have visible shape looks better.
            configuration.contentInsets.top = 8
            configuration.contentInsets.bottom = 8
        }
        return configuration
    }

    static func mediumSecondary(title: String) -> Self {
        var configuration = baseSecondary()
        configuration.title = title
        configuration.contentInsets = .mediumButtonContentInsets
        if #unavailable(iOS 26) {
            // Smaller height when button doesn't have visible shape looks better.
            configuration.contentInsets.top = 8
            configuration.contentInsets.bottom = 8
        }
        return configuration
    }

    static func mediumBorderless(title: String) -> Self {
        var configuration = UIButton.Configuration.borderless()
        configuration.title = title
        configuration.titleAlignment = .center
        configuration.titleTextAttributesTransformer = .defaultFont(.dynamicTypeHeadlineClamped)
        configuration.contentInsets = .mediumButtonContentInsets
        configuration.baseForegroundColor = .Signal.accent
        configuration.baseBackgroundColor = .clear
        return configuration
    }

    static func smallBorderless(title: String) -> Self {
        var configuration = UIButton.Configuration.borderless()
        configuration.title = title
        configuration.titleAlignment = .center
        configuration.titleTextAttributesTransformer = .defaultFont(.dynamicTypeSubheadlineClamped.semibold())
        configuration.contentInsets = .smallButtonContentInsets
        configuration.baseForegroundColor = .Signal.accent
        configuration.baseBackgroundColor = .clear
        return configuration
    }

    static func smallSecondary(title: String) -> Self {
        var configuration = UIButton.Configuration.gray()
        configuration.title = title
        configuration.titleAlignment = .center
        configuration.titleTextAttributesTransformer = .defaultFont(.dynamicTypeSubheadlineClamped.medium())
        configuration.contentInsets = .smallButtonContentInsets
        configuration.baseForegroundColor = .Signal.label
        configuration.background.backgroundColor = .Signal.secondaryFill
        return configuration
    }

    /// Round button that has glass material background on iOS 26+ and no background on older iOS versions.
    static func round(image: UIImage) -> Self {
        var configuration: UIButton.Configuration
        if #available(iOS 26, *) {
            configuration = .glass()
        } else {
            configuration = .plain()
        }
        configuration.image = image
        configuration.baseForegroundColor = .Signal.label
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .init(margin: 10) // 44 dp wide and tall if icon is a standard 24x24
        return configuration
    }

    /// Round button that has glass material background on iOS 26+ and no background on older iOS versions.
    static func round(themeIcon: ThemeIcon) -> Self {
        round(image: Theme.iconImage(themeIcon))
    }

    /// Round button that has glass material background on iOS 26+ and "system chrome" blur on older iOS versions.
    static func roundMaterial(image: UIImage) -> Self {
        var configuration: UIButton.Configuration
        if #available(iOS 26, *) {
            configuration = .glass()
        } else {
            configuration = .plain()

            var backgroundConfiguration = UIBackgroundConfiguration.clear()
            backgroundConfiguration.customView = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
            configuration.background = backgroundConfiguration
        }
        configuration.image = image
        configuration.baseForegroundColor = .Signal.label
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .init(margin: 10) // 44 dp wide and tall if icon is a standard 24x24
        return configuration
    }

    /// Round button with the flat gray background.
    static func roundGray(image: UIImage) -> Self {
        var configuration: UIButton.Configuration = .gray()
        configuration.image = image
        configuration.contentInsets = .init(margin: 10) // 44 dp wide and tall if icon is a standard 24x24
        configuration.baseForegroundColor = .Signal.label
        configuration.baseBackgroundColor = .Signal.tertiaryFill
        configuration.cornerStyle = .capsule
        return configuration
    }

    static func roundMedia(
        image: UIImage,
        size: CGFloat,
        withBackground: Bool = true,
    ) -> Self {
        var configuration: UIButton.Configuration
        if #available(iOS 26, *), withBackground {
            configuration = .glass()
        } else {
            configuration = .plain()
            if withBackground {
                var background = UIBackgroundConfiguration.clear()
                background.customView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
                configuration.background = background
            }
        }
        configuration.image = image
        configuration.baseForegroundColor = .Signal.label
        configuration.cornerStyle = .capsule
        configuration.contentInsets = .init(
            hMargin: 0.5 * (size - image.size.width),
            vMargin: 0.5 * (size - image.size.height),
        )

        return configuration
    }

    static func tintedRoundMedia(
        image: UIImage,
        tintColor: UIColor = .Signal.accent,
        foregroundColor: UIColor = .white,
        size: CGFloat? = nil,
    ) -> Self {
        var configuration: UIButton.Configuration
        if #available(iOS 26, *) {
            configuration = .prominentGlass()
        } else {
            configuration = .bordered()
        }
        configuration.image = image
        configuration.baseForegroundColor = foregroundColor
        configuration.baseBackgroundColor = tintColor
        configuration.cornerStyle = .capsule
        if let size {
            configuration.contentInsets = .init(
                hMargin: 0.5 * (size - image.size.width),
                vMargin: 0.5 * (size - image.size.height),
            )
        }
        return configuration
    }

    static func capsuleMedia(
        title: String,
        buttonHeight: CGFloat,
        withBackground: Bool = true,
    ) -> Self {
        var configuration: UIButton.Configuration
        if #available(iOS 26, *), withBackground {
            configuration = .glass()
        } else {
            configuration = .plain()
            if withBackground {
                var background = UIBackgroundConfiguration.clear()
                background.customView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
                configuration.background = background
            }
        }
        configuration.title = title
        configuration.baseForegroundColor = .Signal.label
        configuration.cornerStyle = .capsule

        // Adjustable vertical content insets to ensure fixed button height.
        let font = UIFont.dynamicTypeFont(ofStandardSize: 17, weight: .medium)
        configuration.attributedTitle?.font = font
        configuration.contentInsets = .init(
            hMargin: 13,
            vMargin: 0.5 * (buttonHeight - font.lineHeight).rounded(.up),
        )

        return configuration
    }
}

// MARK: - UIBarButtonItem

public extension UIBarButtonItem {

    private static var prominentBarButtonItemStyle: UIBarButtonItem.Style {
        if #available(iOS 26, *) { .prominent } else { .done }
    }

    /// Creates a bar button with the given title that performs the action in the provided closure.
    static func button(
        title: String,
        action: @escaping () -> Void,
    ) -> UIBarButtonItem {
        UIBarButtonItem(primaryAction: UIAction(title: title) { _ in action() })
    }

    /// Creates a prominent bar button with the given title that performs the action in the provided closure.
    static func prominentButton(
        title: String,
        action: @escaping () -> Void,
    ) -> UIBarButtonItem {
        let item = button(title: title, action: action)
        item.style = prominentBarButtonItemStyle
        if #available(iOS 26, *) {
            item.tintColor = .Signal.accent
        }
        return item
    }

    /// Creates a bar button with the given icon that performs the action in the provided closure.
    static func button(
        icon: ThemeIcon,
        isProminent: Bool = false,
        action: @escaping () -> Void,
    ) -> UIBarButtonItem {
        .button(image: Theme.iconImage(icon), isProminent: isProminent, action: action)
    }

    /// Creates a bar button with the given image that performs the action in the provided closure.
    static func button(
        image: UIImage,
        isProminent: Bool = false,
        action: @escaping () -> Void,
    ) -> UIBarButtonItem {
        let item = UIBarButtonItem(primaryAction: UIAction(image: image) { _ in action() })
        if isProminent {
            item.style = prominentBarButtonItemStyle
            if #available(iOS 26, *) {
                item.tintColor = .Signal.accent
            }
        }
        return item
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
        action: @escaping () -> Void,
    ) -> UIBarButtonItem {
        let item = UIBarButtonItem(systemItem: systemItem, primaryAction: UIAction { _ in action() })
        if #available(iOS 26, *), item.style == .prominent {
            item.tintColor = .Signal.accent
        }
        return item
    }

    /// Creates a "Cancel" bar button which performs the action in the provided closure.
    static func cancelButton(action: @escaping () -> Void) -> UIBarButtonItem {
        .systemItem(.cancel, action: action)
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
        completion: (() -> Void)? = nil,
    ) -> UIBarButtonItem {
        .cancelButton { [weak viewController] in
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
        completion: (() -> Void)? = nil,
    ) -> UIBarButtonItem {
        .cancelButton { [weak viewController] in
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
        animated: Bool = true,
    ) -> UIBarButtonItem {
        .cancelButton { [weak navigationController] in
            navigationController?.popViewController(animated: animated)
        }
    }

    /// Creates a "Done" bar button which performs the action in the provided closure.
    static func doneButton(action: @escaping () -> Void) -> UIBarButtonItem {
        .systemItem(.done, action: action)
    }

    /// Creates a "X" (Close) bar button which performs the action in the provided closure.
    static func closeButton(action: @escaping () -> Void) -> UIBarButtonItem {
        if #available(iOS 26, *) {
            .systemItem(.close, action: action)
        } else {
            // This looks better without the circular background that system item has.
            .button(icon: .buttonX, action: action)
        }
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
        completion: (() -> Void)? = nil,
    ) -> UIBarButtonItem {
        let systemItem: SystemItem = if #available(iOS 26, *) { .close } else { .done }
        return .systemItem(systemItem) { [weak viewController] in
            viewController?.dismiss(animated: animated, completion: completion)
        }
    }

    /// Creates ••• bar button that presents a popup menu with the provided actions.
    static func contextMenuButton(actions: [UIAction]) -> UIBarButtonItem {
        let buttonImageName: String = if #available(iOS 26, *) { "more" } else { "more-circle" }
        let barButtonItem = UIBarButtonItem(
            image: UIImage(named: buttonImageName),
            menu: UIMenu(children: actions),
        )
        barButtonItem.landscapeImagePhone = UIImage(named: buttonImageName + "-20")
        return barButtonItem
    }

    /// Creates a prominent button that uses "Set" as the title on iOS 15-18 and a system checkmark on iOS 26 and later.
    static func setButton(action: @escaping () -> Void) -> UIBarButtonItem {
        if #available(iOS 26, *) {
            // iOS 26 done buttons appear as a big blue checkmark
            .systemItem(.done, action: action)
        } else {
            // For iOS 18 and older, we want to use the text "Set"
            .prominentButton(title: CommonStrings.setButton, action: action)
        }
    }

    /// Creates a prominent "Next" button.
    static func nextButton(action: @escaping () -> Void) -> UIBarButtonItem {
        .prominentButton(title: CommonStrings.nextButton, action: action)
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

// MARK: -

#if DEBUG

private class ButtonPreviewViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let buttonStack = UIStackView(arrangedSubviews: [
            UIButton(configuration: .largePrimary(title: "Large Primary")),
            UIButton(configuration: .largeSecondary(title: "Large Secondary")),
            UIButton(configuration: .mediumSecondary(title: "Medium Secondary")),
            UIButton(configuration: .mediumBorderless(title: "Medium Borderless")),
            UIButton(configuration: .smallSecondary(title: "Small Secondary")),
            UIButton(configuration: .smallBorderless(title: "Small Borderless")),
            UIStackView(arrangedSubviews: [
                UILabel.subheadlineLabel(text: "Round:"),
                .spacer(withWidth: 12),
                UIButton(configuration: .round(themeIcon: .buttonX)),
            ]),
            UIStackView(arrangedSubviews: [
                UILabel.subheadlineLabel(text: "Round Gray:"),
                .spacer(withWidth: 12),
                UIButton(configuration: .roundGray(image: Theme.iconImage(.buttonX))),
            ]),
        ])
        buttonStack.axis = .vertical
        buttonStack.alignment = .center
        buttonStack.spacing = 16
        view.addSubview(buttonStack)
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            buttonStack.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor, constant: 16),
            buttonStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            buttonStack.bottomAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.bottomAnchor),
        ])
    }
}

@available(iOS 17, *)
#Preview("Button Styles") {
    return ButtonPreviewViewController(nibName: nil, bundle: nil)
}

#endif
