//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI
import SignalMessaging
import SafariServices

class UsernameEducationViewController: OWSTableViewController2 {

    private enum Constants {
        static let headerHeight: CGFloat = 44.0
        static let iconSize: CGFloat = 64.0
        static let itemIconSize: CGFloat = 48.0
        static let itemMargin: CGFloat = 16.0

        static let continueButtonInsets: UIEdgeInsets = .init(
            top: 16.0,
            leading: 36.0,
            bottom: 48,
            trailing: 36.0
        )
        static let continueButtonEdgeInsets: UIEdgeInsets = .init(
            hMargin: 0,
            vMargin: 16
        )

        static let pillSize: CGSize = .init(width: 36, height: 5)
        static let pillTopMargin: CGFloat = 12.0

        static let learnMoreURL: String = "https://support.signal.org/hc/articles/5389476324250"
    }

    /// Completion called once the user taps 'Continue' in the education prompt
    var continueCompletion: (() -> Void)?

    public var prefersNavigationBarHidden: Bool { true }

    // MARK: Lifecycle

    public override func viewDidLoad() {
        view.backgroundColor = Theme.tableView2BackgroundColor
        rebuildTableContents()
        topHeader = pillHeader
        bottomFooter = continueButton
        setColorsForCurrentTheme()
        super.viewDidLoad()
    }

    public override func themeDidChange() {
        super.themeDidChange()
        setColorsForCurrentTheme()
        rebuildTableContents()
    }

    // MARK: Views

    private lazy var pillHeader: UIView = {
        let headerView = UIView()

        headerView.addSubview(pillView)
        headerView.autoSetDimension(.height, toSize: Constants.headerHeight)

        pillView.autoPinEdge(toSuperviewEdge: .top, withInset: Constants.pillTopMargin)
        pillView.autoHCenterInSuperview()

        return headerView
    }()

    private lazy var pillView: PillView = {
        let pillView = PillView()
        pillView.autoSetDimensions(to: Constants.pillSize)
        return pillView
    }()

    private lazy var continueButton: UIView = {
        let footerView = UIView()
        let continueButton = OWSFlatButton.insetButton(
            title: CommonStrings.continueButton,
            font: UIFont.dynamicTypeBodyClamped.semibold(),
            titleColor: .white,
            backgroundColor: .ows_accentBlue,
            target: self,
            selector: #selector(didTapContinue))
        footerView.addSubview(continueButton)

        continueButton.contentEdgeInsets = Constants.continueButtonEdgeInsets
        continueButton.autoPinEdgesToSuperviewEdges(with: Constants.continueButtonInsets)

        return footerView
    }()

    // MARK: TableView config

    private func rebuildTableContents() {
        let contents = OWSTableContents()

        let headerSection = OWSTableSection()
        headerSection.hasBackground = false
        headerSection.add(createTableHeader())

        let section = OWSTableSection()
        section.hasBackground = false

        section.add(
            createTableItem(
                iconName: "number-color-48",
                description: OWSLocalizedString(
                    "USERNAME_DISCRIMINATOR_DESCRIPTION",
                    comment: "Description of username discriminator digits")))

        section.add(
            createTableItem(
                iconName: "link-color-48",
                description: OWSLocalizedString(
                    "USERNAME_LINK_DESCRIPTION",
                    comment: "Description of username link")))

        section.add(
            createTableItem(
                iconName: "lock-color-48",
                description: OWSLocalizedString(
                    "USERNAME_DISCOVERY_DESCRIPTION",
                    comment: "Description of how to update discovery")))

        section.add(createLearnMore())

        contents.addSections([
            headerSection,
            section
        ])

        self.contents = contents
    }

    private func createTableHeader() -> OWSTableItem {
        return OWSTableItem {
            let cell = OWSTableItem.newCell()

            let headerView = Self.HeaderView(withIconSize: Constants.iconSize)
            cell.addSubview(headerView)

            headerView.autoPinEdgesToSuperviewMargins()
            return cell
        }
    }

    private func createLearnMore() -> OWSTableItem {
        return OWSTableItem {
            let cell = OWSTableItem.newCell()

            let button = OWSFlatButton.button(
                title: CommonStrings.learnMore,
                font: UIFont.dynamicTypeSubheadlineClamped,
                titleColor: Theme.accentBlueColor,
                backgroundColor: .clear,
                target: self,
                selector: #selector(self.didTapLearnMore))

            cell.addSubview(button)
            button.autoPinEdgesToSuperviewMargins()

            return cell
        }
    }

    private func createTableItem(iconName: String, description: String) -> OWSTableItem {
        return OWSTableItem {
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none

            let stackView = UIStackView()
            stackView.spacing = Constants.itemMargin

            cell.addSubview(stackView)

            stackView.autoPinEdgesToSuperviewMargins(with: .init(
                hMargin: Constants.itemMargin,
                vMargin: 0.0))
            stackView.alignment = .center

            let iconView = UIImageView(image: UIImage(named: iconName))
            iconView.contentMode = .scaleAspectFit
            iconView.autoPinToSquareAspectRatio()
            iconView.autoSetDimension(.height, toSize: Constants.itemIconSize)

            stackView.addArrangedSubview(iconView)

            let titleLabel = UILabel()
            titleLabel.text = description
            titleLabel.font = UIFont.dynamicTypeSubheadlineClamped
            titleLabel.numberOfLines = 0
            titleLabel.textAlignment = .left
            titleLabel.lineBreakMode = .byWordWrapping
            titleLabel.textColor = Theme.secondaryTextAndIconColor
            stackView.addArrangedSubview(titleLabel)

            return cell
        }
    }

    // MARK: Actions

    @objc
    private func didTapContinue() {
        dismiss(animated: true) {
            self.continueCompletion?()
        }
    }

    @objc
    private func didTapLearnMore() {
        let vc = SFSafariViewController(url: URL(string: Constants.learnMoreURL)!)
        present(vc, animated: true, completion: nil)
    }

    // MARK: Theme

    private func setColorsForCurrentTheme() {
        pillView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_gray20
    }
}

extension UsernameEducationViewController {
    class HeaderView: UIView {

        private let iconSize: CGFloat

        // MARK: Init

        init(withIconSize iconSize: CGFloat) {
            self.iconSize = iconSize

            super.init(frame: .zero)

            addSubview(stackView)
            stackView.autoPinEdgesToSuperviewEdges()

            updateFontsForCurrentPreferredContentSize()
            setColorsForCurrentTheme()
        }

        @available(*, unavailable, message: "Use other constructor")
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        private let iconImage: UIImage = Theme.iconImage(.settingsMention)

        // MARK: Views

        private lazy var iconImageView: UIImageView = {
            UIImageView(image: iconImage)
        }()

        /// Displays an icon over a circular, square-aspect-ratio, colored
        /// background.
        private lazy var iconView: UIView = {
            let backgroundView = UIView()
            backgroundView.layer.masksToBounds = true
            backgroundView.layer.cornerRadius = iconSize / 2

            backgroundView.autoPinToSquareAspectRatio()
            backgroundView.autoSetDimension(.height, toSize: iconSize)

            backgroundView.addSubview(iconImageView)
            iconImageView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(margin: iconSize / 4))
            iconImageView.backgroundColor = .clear

            return backgroundView
        }()

        private lazy var usernameTitleLabel: UILabel = {
            let label = UILabel()
            label.text = OWSLocalizedString(
                "USERNAME_EDUCATION_TITLE",
                comment: "Title to set up signal username")
            label.numberOfLines = 0
            label.textAlignment = .center
            return label
        }()

        private lazy var stackView: OWSStackView = {
            let stack = OWSStackView(
                name: "Username Education Header Stack",
                arrangedSubviews: [
                    iconView,
                    usernameTitleLabel
                ]
            )

            stack.axis = .vertical
            stack.alignment = .center
            stack.distribution = .equalSpacing
            stack.spacing = 16

            return stack
        }()

        // MARK: - Style views

        func updateFontsForCurrentPreferredContentSize() {
            usernameTitleLabel.font = .dynamicTypeTitle1Clamped.semibold()
        }

        func setColorsForCurrentTheme() {
            iconImageView.image = iconImage
                .tintedImage(color: Theme.isDarkThemeEnabled ? .ows_gray02 : .ows_gray90)

            iconView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_white

            usernameTitleLabel.textColor = Theme.primaryTextColor
        }
    }
}
