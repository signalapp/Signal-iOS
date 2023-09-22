//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalMessaging

// MARK: - AppIcon

enum CustomAppIcon: String {
    case white = "AppIcon-white"
    case color = "AppIcon-color"
    case dark = "AppIcon-dark"
    case darkVariant = "AppIcon-dark-variant"
    case chat = "AppIcon-chat"
    case bubbles = "AppIcon-bubbles"
    case yellow = "AppIcon-yellow"
    case news = "AppIcon-news"
    case notes = "AppIcon-notes"
    case weather = "AppIcon-weather"
    case wave = "AppIcon-wave"

    static func iconIsSelected(customIcon: CustomAppIcon?) -> Bool {
        UIApplication.shared.alternateIconName == customIcon?.rawValue
    }

    /// The name for the preview image for the default app icon.
    ///
    /// If you try to load the full app icon set into a `UIImage`, it loads a
    /// low-resolution version of it, so this needs to be a separate image set.
    /// Even Apple's own demo project has low-resolution picker images
    /// because they didn't do this.
    static let defaultAppIconPreviewImageName = "AppIcon_preview"

    static var currentIconImageName: String {
        UIApplication.shared.alternateIconName ?? defaultAppIconPreviewImageName
    }

    /// Indicates if the icon should be rendered with a shadow in the picker.
    ///
    /// Some icons have a white background and should show a subtle
    /// shadow in the picker to separate it from the background.
    var shouldShowShadow: Bool {
        switch self {
        case .color, .dark, .darkVariant, .chat, .yellow, .news, .notes, .weather, .wave:
            return false
        case .white, .bubbles:
            return true
        }
    }
}

// MARK: - AppIconLearnMoreTableViewController

private class AppIconLearnMoreTableViewController: OWSTableViewController2 {
    override func viewDidLoad() {
        super.viewDidLoad()
        updateTableContents()

        navigationItem.leftBarButtonItem = .init(
            barButtonSystemItem: .done,
            target: self, action: #selector(didTapDone),
            accessibilityIdentifier: "AppIconLearnMoreTableViewController.done"
        )
    }

    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    private func updateTableContents() {
        let contents = OWSTableContents()

        let topSection = OWSTableSection()
        topSection.headerAttributedTitle = NSAttributedString(
            string: OWSLocalizedString(
                "SETTINGS_APP_ICON_EDUCATION_APP_NAME",
                comment: "Information on sheet about changing the app icon - first line"
            )
        )
        .styled(
            with: .font(.dynamicTypeSubheadlineClamped),
            .color(Theme.secondaryTextAndIconColor)
        )
        topSection.add(.init(customCellBlock: { [weak self] in
            let homescreenImageName = UIDevice.current.isIPad ? "homescreen_ipados" : "homescreen_ios"
            return self?.createCell(
                with: homescreenImageName,
                insets: .init(hMargin: 48, vMargin: 24)
            ) ?? UITableViewCell()
        }))
        topSection.shouldDisableCellSelection = true

        let bottomSection = OWSTableSection()
        bottomSection.headerAttributedTitle = NSAttributedString(
            string: OWSLocalizedString(
                "SETTINGS_APP_ICON_EDUCATION_HOME_SCREEN_DOCK",
                comment: "Information on sheet about changing the app icon - second line"
            )
        )
        .styled(
            with: .font(.dynamicTypeSubheadlineClamped),
            .color(Theme.secondaryTextAndIconColor)
        )
        bottomSection.add(.init(customCellBlock: { [weak self] in
            let dockImageName = UIDevice.current.isIPad ? "dock_ipados" : "dock_ios"
            return self?.createCell(
                with: dockImageName,
                insets: .init(top: 0, leading: 16, bottom: 29, trailing: 16)
            ) ?? UITableViewCell()
        }))
        bottomSection.shouldDisableCellSelection = true

        contents.add(sections: [topSection, bottomSection])
        self.contents = contents
    }

    private func createCell(
        with image: String,
        insets: UIEdgeInsets
    ) -> UITableViewCell {
        let cell = OWSTableItem.newCell()
        let image = UIImage(named: image)
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        cell.contentView.addSubview(imageView)
        imageView.autoPinEdgesToSuperviewEdges(with: insets)
        return cell
    }

    @objc
    private func didTapDone() {
        dismiss(animated: true)
    }
}

// MARK: - AppIconSettingsTableViewControllerDelegate

protocol AppIconSettingsTableViewControllerDelegate: AnyObject {
    func didChangeIcon()
}

// MARK: - AppIconSettingsTableViewController

class AppIconSettingsTableViewController: OWSTableViewController2 {

    // MARK: Static properties

    private static let customIcons: [[CustomAppIcon?]] = [
        [.none, .white, .color, .dark],
        [.darkVariant, .chat, .bubbles, .yellow],
        [.news, .notes, .weather, .wave],
    ]

    /// This URL itself is not used. The action is overridden in the text view delegate function.
    private static let learnMoreURL = URL(string: "https://support.signal.org/")!

    // MARK: Properties

    weak var iconDelegate: AppIconSettingsTableViewControllerDelegate?
    private var stackView: UIStackView?

    // MARK: View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = OWSLocalizedString(
            "SETTINGS_APP_ICON_TITLE",
            comment: "The title for the app icon selection settings page."
        )
        updateTableContents()
    }

    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    // MARK: Table setup

    private func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()
        section.add(.init(customCellBlock: { [weak self] in
            guard let self else { return UITableViewCell() }
            return self.buildIconSelectionCell()
        }))
        section.footerAttributedTitle = NSAttributedString.composed(of: [
            OWSLocalizedString(
                "SETTINGS_APP_ICON_FOOTER",
                comment: "The footer for the app icon selection settings page."
            ),
            "\n",
            CommonStrings.learnMore.styled(with: .link(Self.learnMoreURL))
        ])
        .styled(
            with: .font(.dynamicTypeCaption1Clamped),
            .color(Theme.secondaryTextAndIconColor)
        )
        section.footerTextViewDelegate = self
        section.shouldDisableCellSelection = true

        contents.add(section)
        self.contents = contents
    }

    private func buildIconSelectionCell() -> UITableViewCell {
        let rows = Self.customIcons.map { row in
            let icons = row.map { icon in
                IconButton(icon: icon) { [weak self] in
                    self?.didTapIcon(icon)
                }
            }
            let stackView = UIStackView(arrangedSubviews: [SpacerView(preferredWidth: 0)] + icons + [SpacerView(preferredWidth: 0)])
            stackView.axis = .horizontal
            stackView.distribution = .equalSpacing
            stackView.alignment = .center
            return stackView
        }

        let stackView = UIStackView(arrangedSubviews: rows)
        stackView.axis = .vertical
        stackView.spacing = 32
        stackView.distribution = .fillEqually
        stackView.alignment = .fill

        let iconSize: CGFloat
        if UIDevice.current.isNarrowerThanIPhone6 {
            iconSize = 56
        } else {
            iconSize = 60
        }

        stackView.arrangedSubviews
            .compactMap { $0 as? UIStackView }
            .flatMap(\.arrangedSubviews)
            .forEach { view in
                if view is SpacerView {
                    return
                }
                view.autoSetDimensions(to: .square(iconSize))
            }

        self.stackView = stackView
        let cell = OWSTableItem.newCell()
        cell.contentView.addSubview(stackView)
        // Subtract off the cell inner margins in favor of
        // the stack views' spacer views with equal spacing.
        stackView.autoPinEdgesToSuperviewMargins(with: .init(hMargin: -Self.cellHInnerMargin, vMargin: 24))
        return cell
    }

    private func didTapLearnMore() {
        let learnMoreViewController = AppIconLearnMoreTableViewController()
        let navigationController = OWSNavigationController(rootViewController: learnMoreViewController)
        presentFormSheet(navigationController, animated: true)
    }

    private func didTapIcon(_ icon: CustomAppIcon?) {
        guard !CustomAppIcon.iconIsSelected(customIcon: icon) else { return }

        UIApplication.shared.setAlternateIconName(icon?.rawValue) { error in
            if let error {
                owsFailDebug("Failed to update app icon: \(error)")
            }
        }
        updateIconSelection()
        iconDelegate?.didChangeIcon()
    }

    private func updateIconSelection() {
        let animator = UIViewPropertyAnimator(duration: 0.15, springDamping: 1, springResponse: 0.15)
        animator.addAnimations {
            self.stackView?.arrangedSubviews
                .compactMap { $0 as? UIStackView }
                .flatMap(\.arrangedSubviews)
                .forEach { view in
                    guard let iconButton = view as? IconButton else { return }
                    iconButton.updateSelectedState()
                }
        }
        animator.startAnimation()
    }

    private class IconButton: UIView {
        static let iconCornerRadius: CGFloat = 12
        static let selectedOutlineCornerRadius: CGFloat = 16

        let icon: CustomAppIcon?
        private let button: UIView
        private let selectedOutlineView: UIView

        init(icon: CustomAppIcon?, action: @escaping () -> Void) {
            self.icon = icon
            self.button = Self.makeButton(for: icon, action: action)
            self.selectedOutlineView = UIView.container()
            super.init(frame: .zero)

            self.addSubview(selectedOutlineView)
            selectedOutlineView.autoPinEdgesToSuperviewEdges()
            selectedOutlineView.layer.cornerRadius = Self.selectedOutlineCornerRadius
            let borderColor: UIColor = Theme.isDarkThemeEnabled ? .ows_gray05 : .ows_black
            selectedOutlineView.layer.borderColor = borderColor.cgColor

            selectedOutlineView.addSubview(button)
            button.autoPinEdgesToSuperviewEdges()

            updateSelectedState()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func updateSelectedState() {
            if CustomAppIcon.iconIsSelected(customIcon: icon) {
                button.transform = .scale(0.8)
                selectedOutlineView.layer.borderWidth = 3
            } else {
                button.transform = .identity
                selectedOutlineView.layer.borderWidth = 0
            }
        }

        private static func makeButton(for icon: CustomAppIcon?, action: @escaping () -> Void) -> UIView {
            let image = UIImage(named: icon?.rawValue ?? CustomAppIcon.defaultAppIconPreviewImageName)
            let button = OWSButton(block: action)
            button.setImage(image, for: .normal)
            button.clipsToBounds = true
            button.layer.cornerRadius = iconCornerRadius

            if icon?.shouldShowShadow == true {
                let backgroundView = UIView.container()
                backgroundView.setShadow(radius: 1, opacity: 0.24, offset: .zero, color: .ows_black)
                backgroundView.addSubview(button)
                button.autoPinEdgesToSuperviewEdges()
                return backgroundView
            }

            return button
        }
    }
}

// MARK: UITextViewDelegate

extension AppIconSettingsTableViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        if url == Self.learnMoreURL {
            didTapLearnMore()
        }
        return false
    }
}
