//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol AppIconSettingsTableViewControllerDelegate: AnyObject {
    func didChangeIcon()
}

final class AppIconSettingsTableViewController: OWSTableViewController2 {

    // MARK: Static properties

    private static let customIcons: [[AppIcon]] = [
        [.default, .white, .color, .night],
        [.nightVariant, .chat, .bubbles, .yellow],
        [.news, .notes, .weather, .waves],
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

    private func didTapIcon(_ icon: AppIcon) {
        guard UIApplication.shared.currentAppIcon != icon else { return }

        UIApplication.shared.setAlternateIconName(icon.alternateIconName) { error in
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

        let icon: AppIcon?
        private let button: UIView
        private let selectedOutlineView: UIView

        init(icon: AppIcon, action: @escaping () -> Void) {
            self.icon = icon
            self.button = Self.makeButton(for: icon, action: action)
            self.selectedOutlineView = UIView.container()
            super.init(frame: .zero)

            self.addSubview(selectedOutlineView)
            selectedOutlineView.autoPinEdgesToSuperviewEdges()
            selectedOutlineView.layer.cornerRadius = Self.selectedOutlineCornerRadius
            selectedOutlineView.layer.cornerCurve = .continuous
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
            if UIApplication.shared.currentAppIcon == icon {
                button.transform = .scale(0.8)
                selectedOutlineView.layer.borderWidth = 3
            } else {
                button.transform = .identity
                selectedOutlineView.layer.borderWidth = 0
            }
        }

        private static func makeButton(for icon: AppIcon, action: @escaping () -> Void) -> UIView {
            let image = UIImage(resource: icon.previewImageResource)
            let button = OWSButton(block: action)
            button.setImage(image, for: .normal)
            button.clipsToBounds = true
            button.layer.cornerRadius = iconCornerRadius
            button.layer.cornerCurve = .continuous

            if icon.shouldShowShadow {
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
