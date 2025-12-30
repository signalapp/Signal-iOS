//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SafariServices
import SignalServiceKit
import SignalUI

class UsernameEducationViewController: OWSTableViewController2 {

    private enum Constants {
        static let headerHeight: CGFloat = 44.0
        static let itemIconSize: CGFloat = 48.0
        static let itemMargin: CGFloat = 20.0

        static let pillSize: CGSize = .init(width: 36, height: 5)
        static let pillTopMargin: CGFloat = 12.0
    }

    /// Completion called once the user taps 'Continue' in the education prompt
    var continueCompletion: (() -> Void)?

    var prefersNavigationBarHidden: Bool { true }

    // MARK: Lifecycle

    override init() {
        super.init()

        topHeader = pillHeader
        bottomFooter = footerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.tableView2BackgroundColor
        rebuildTableContents()
        setColorsForCurrentTheme()
        tableView.alwaysBounceVertical = false
    }

    override func themeDidChange() {
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

    private lazy var footerView: UIView = {
        let continueButton = UIButton(
            configuration: .largePrimary(title: OWSLocalizedString(
                "USERNAME_EDUCATION_SET_UP_BUTTON",
                comment: "Label for the 'set up' button on the username education sheet",
            )),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapContinue()
            },
        )

        let dismissButton = UIButton(
            configuration: .largeSecondary(title: CommonStrings.notNowButton),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapDismiss()
            },
        )

        let stackView = UIStackView.verticalButtonStack(
            buttons: [continueButton, dismissButton],
            isFullWidthButtons: true,
        )

        let container = UIView()
        container.preservesSuperviewLayoutMargins = true
        container.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: container.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: container.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: container.layoutMarginsGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }()

    // MARK: TableView config

    private func rebuildTableContents() {
        let contents = OWSTableContents()

        let headerSection = OWSTableSection()
        headerSection.hasBackground = false
        headerSection.add(createTableHeader())

        let section = OWSTableSection()
        section.hasBackground = false

        section.add(createTableItem(
            iconName: "phone-48-color",
            title: OWSLocalizedString(
                "USERNAME_EDUCATION_PRIVACY_TITLE",
                comment: "Title for phone number privacy section of the username education sheet",
            ),
            description: OWSLocalizedString(
                "USERNAME_EDUCATION_PRIVACY_DESCRIPTION",
                comment: "Description of phone number privacy on the username education sheet",
            ),
        ))

        section.add(createTableItem(
            iconName: "usernames-48-color",
            title: OWSLocalizedString(
                "USERNAME_EDUCATION_USERNAME_TITLE",
                comment: "Title for usernames section on the username education sheet",
            ),
            description: OWSLocalizedString(
                "USERNAME_EDUCATION_USERNAME_DESCRIPTION",
                comment: "Description of usernames on the username education sheet",
            ),
        ))

        section.add(createTableItem(
            iconName: "qr-codes-48-color",
            title: OWSLocalizedString(
                "USERNAME_EDUCATION_LINK_TITLE",
                comment: "Title for the username links and QR codes section on the username education sheet",
            ),
            description: OWSLocalizedString(
                "USERNAME_EDUCATION_LINK_DESCRIPTION",
                comment: "Description of username links and QR codes on the username education sheet",
            ),
            isLastItem: true,
        ))

        contents.add(sections: [
            headerSection,
            section,
        ])

        self.contents = contents
    }

    private func createTableHeader() -> OWSTableItem {
        return OWSTableItem {
            let cell = OWSTableItem.newCell()

            let headerView = Self.HeaderView()
            cell.addSubview(headerView)

            headerView.autoPinEdgesToSuperviewMargins()
            return cell
        }
    }

    private func createTableItem(
        iconName: String,
        title: String,
        description: String,
        isLastItem: Bool = false,
    ) -> OWSTableItem {
        return OWSTableItem {
            let cell = OWSTableItem.newCell()
            cell.selectionStyle = .none

            let stackView = UIStackView()
            stackView.spacing = Constants.itemMargin

            cell.addSubview(stackView)

            stackView.autoPinLeadingToSuperviewMargin(withInset: Constants.itemMargin)
            stackView.autoPinTrailingToSuperviewMargin(withInset: Constants.itemMargin)
            stackView.autoPinEdge(toSuperviewEdge: .top, withInset: 0)
            stackView.autoPinEdge(
                toSuperviewEdge: .bottom,
                withInset: isLastItem ? 0 : Constants.itemMargin * 2,
            )
            stackView.alignment = .top

            let iconView = UIImageView(image: UIImage(named: iconName))
            iconView.contentMode = .scaleAspectFit
            iconView.autoPinToSquareAspectRatio()
            iconView.autoSetDimension(.height, toSize: Constants.itemIconSize)

            stackView.addArrangedSubview(iconView)

            let titleLabel = UILabel()
            titleLabel.text = title
            titleLabel.font = UIFont.dynamicTypeBody
            titleLabel.numberOfLines = 0
            titleLabel.textAlignment = .left
            titleLabel.lineBreakMode = .byWordWrapping
            titleLabel.textColor = Theme.primaryTextColor

            let bodyLabel = UILabel()
            bodyLabel.text = description
            bodyLabel.font = UIFont.dynamicTypeSubheadlineClamped
            bodyLabel.numberOfLines = 0
            bodyLabel.textAlignment = .left
            bodyLabel.lineBreakMode = .byWordWrapping
            bodyLabel.textColor = Theme.secondaryTextAndIconColor

            let textStack = UIStackView(
                arrangedSubviews: [
                    titleLabel,
                    bodyLabel,
                ],
            )
            textStack.axis = .vertical
            textStack.spacing = 4

            stackView.addArrangedSubview(textStack)

            return cell
        }
    }

    // MARK: Actions

    private func didTapContinue() {
        dismiss(animated: true) {
            self.continueCompletion?()
        }
    }

    private func didTapDismiss() {
        dismiss(animated: true)
    }

    // MARK: Theme

    private func setColorsForCurrentTheme() {
        pillView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_gray20
    }
}

extension UsernameEducationViewController {
    class HeaderView: UIView {

        // MARK: Init

        init() {
            super.init(frame: .zero)

            addSubview(usernameTitleLabel)
            usernameTitleLabel.autoPinEdgesToSuperviewEdges()

            updateFontsForCurrentPreferredContentSize()
            setColorsForCurrentTheme()
        }

        @available(*, unavailable, message: "Use other constructor")
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // MARK: Views

        private lazy var usernameTitleLabel: UILabel = {
            let label = UILabel()
            label.text = OWSLocalizedString(
                "USERNAME_EDUCATION_TITLE",
                comment: "Title to set up signal username",
            )
            label.numberOfLines = 0
            label.textAlignment = .center
            return label
        }()

        // MARK: - Style views

        func updateFontsForCurrentPreferredContentSize() {
            usernameTitleLabel.font = .dynamicTypeTitle1Clamped.semibold()
        }

        func setColorsForCurrentTheme() {
            usernameTitleLabel.textColor = Theme.primaryTextColor
        }
    }
}
