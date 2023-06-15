//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalMessaging
import SignalUI

class UsernameLinkQRCodeViewController: OWSTableViewController2 {
    private let usernameLink: Usernames.UsernameLink

    init(usernameLink: Usernames.UsernameLink) {
        self.usernameLink = usernameLink
        super.init()
    }

    // MARK: - Views

    /// A horizontal stack view that centers its fixed-width content subviews.
    private class CenteringStackView: UIStackView {
        init(centeredSubviews: [UIView]) {
            super.init(frame: .zero)

            let leftSpacer = SpacerView()
            let rightSpacer = SpacerView()

            addArrangedSubviews([leftSpacer] + centeredSubviews + [rightSpacer])
            axis = .horizontal
            alignment = .center
            spacing = 8

            leftSpacer.autoPinWidth(toWidthOf: rightSpacer)
        }

        required init(coder: NSCoder) {
            owsFail("Not implemented")
        }
    }

    // MARK: QR Code

    /// Builds the QR code view, including the QR code, colored background, and
    /// display of the current username.
    private func buildQRCodeView() -> UIView {
        let qrCodeImageView: UIImageView = {
            let imageView = UIImageView(image: Theme
                .iconImage(.attachmentCamera)
                .asTintedImage(color: .ows_white)
            )

            imageView.autoPinToSquareAspectRatio()
            imageView.layer.cornerRadius = 12

            return imageView
        }()

        let copyUsernameLabel: UILabel = {
            let label = UILabel()

            label.font = .dynamicTypeHeadline.semibold()
            label.numberOfLines = 0
            label.lineBreakMode = .byCharWrapping
            label.textColor = .ows_white
            label.text = usernameLink.username

            return label
        }()

        let copyUsernameView: UIView = {
            let copyIconImage = Theme
                .iconImage(.copy24, isDarkThemeEnabled: false) // hardcode light theme to get outline
                .asTintedImage(color: .ows_white)

            let copyImageView = UIImageView(image: copyIconImage)
            copyImageView.autoSetDimensions(to: .square(24))

            return CenteringStackView(centeredSubviews: [
                copyImageView,
                copyUsernameLabel
            ])
        }()

        let wrapperView = UIView()

        // TODO: when we offer more colors, we need to persist/load this.
        wrapperView.backgroundColor = .ows_signalBlue
        wrapperView.layer.cornerRadius = 24
        wrapperView.layoutMargins = UIEdgeInsets(hMargin: 40, vMargin: 32)

        wrapperView.addSubview(qrCodeImageView)
        wrapperView.addSubview(copyUsernameView)

        qrCodeImageView.autoPinTopToSuperviewMargin()
        qrCodeImageView.autoPinLeadingToSuperviewMargin()
        qrCodeImageView.autoPinTrailingToSuperviewMargin()

        qrCodeImageView.autoPinEdge(.bottom, to: .top, of: copyUsernameView, withOffset: -16)

        copyUsernameView.autoPinLeadingToSuperviewMargin()
        copyUsernameView.autoPinTrailingToSuperviewMargin()
        copyUsernameView.autoPinBottomToSuperviewMargin()

        return wrapperView
    }

    // MARK: Share and Color buttons

    private func buildActionButton(
        text: String,
        icon: ThemeIcon,
        block: @escaping () -> Void
    ) -> SettingsHeaderButton {
        let button = SettingsHeaderButton(
            text: text,
            icon: icon,
            backgroundColor: OWSTableViewController2.cellBackgroundColor(
                isUsingPresentedStyle: true
            ),
            isEnabled: true,
            block: block
        )

        button.autoSetDimension(
            .width,
            toSize: 100,
            relation: .greaterThanOrEqual
        )

        return button
    }

    private func buildActionButtonsView() -> UIView {
        let shareQRCodeButton = buildActionButton(
            text: OWSLocalizedString(
                "USERNAME_LINK_QR_CODE_VIEW_SHARE_BUTTON",
                comment: "Title for a button to share your username link QR code. Lowercase styling is intentional."
            ),
            icon: .messageActionShare24,
            block: {
                // TODO: implement button
            }
        )

        let colorQRCodeButton = buildActionButton(
            text: OWSLocalizedString(
                "USERNAME_LINK_QR_CODE_VIEW_COLOR_BUTTON",
                comment: "Title for a button to pick the color of your username link QR code. Lowercase styling is intentional."
            ),
            icon: .color24,
            block: {
                // TODO: Implement button
            }
        )

        let stackView = CenteringStackView(centeredSubviews: [
            shareQRCodeButton,
            colorQRCodeButton
        ])

        shareQRCodeButton.autoPinWidth(toWidthOf: colorQRCodeButton)

        return stackView
    }

    // MARK: Disclaimer text

    private func buildDisclaimerLabel() -> UILabel {
        let label = UILabel()
        label.font = .dynamicTypeCaption1
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = Theme.secondaryTextAndIconColor
        label.text = OWSLocalizedString(
            "USERNAME_LINK_QR_CODE_VIEW_DISCLAIMER_LABEL",
            comment: "Text for a label explaining what the username link and QR code give others access to."
        )

        return label
    }

    // MARK: Reset button

    private func buildResetButtonView() -> UIView {
        let button = OWSButton(block: {
            // TODO: Implement button
        })

        button.setTitle(OWSLocalizedString(
            "USERNAME_LINK_QR_CODE_VIEW_RESET_BUTTON_TITLE",
            comment: "Title for a button that allows users to reset their username link and QR code."
        ), for: .normal)

        button.contentEdgeInsets = UIEdgeInsets(hMargin: 16, vMargin: 6)
        button.backgroundColor = .ows_white.withAlphaComponent(0.7)
        button.titleLabel?.font = .dynamicTypeBody2.bold()
        button.titleLabel?.textAlignment = .center
        button.setTitleColor(Theme.primaryTextColor, for: .normal)

        button.sizeToFit()
        button.layer.cornerRadius = button.height / 2

        button.dimsWhenHighlighted = true

        return CenteringStackView(centeredSubviews: [button])
    }

    // MARK: Put it all together

    private func buildTableContents() {
        let topSection = OWSTableSection(items: [
            .wrapping(
                viewBlock: { [weak self] in
                    return self?.buildQRCodeView()
                },
                margins: UIEdgeInsets(top: 32, leading: 48, bottom: 12, trailing: 48)
            ),
            .wrapping(
                viewBlock: { [weak self] in
                    return self?.buildActionButtonsView()
                },
                margins: UIEdgeInsets(top: 12, leading: 16, bottom: 24, trailing: 16)
            )
        ])

        let linkCellSection = OWSTableSection(items: [
            OWSTableItem(
                customCellBlock: { [weak self] in
                    guard let self else { return UITableViewCell() }

                    return OWSTableItem.buildImageCell(
                        image: UIImage(named: "link-diagonal"),
                        itemName: self.usernameLink.asUrl.absoluteString,
                        maxItemNameLines: 1,
                        accessoryType: .disclosureIndicator
                    )
                },
                actionBlock: {
                    // TODO: Implement action
                }
            )
        ])

        let bottomSection = OWSTableSection(items: [
            .wrapping(
                viewBlock: { [weak self] in
                    self?.buildDisclaimerLabel()
                },
                margins: UIEdgeInsets(top: 28, leading: 32, bottom: 12, trailing: 32)
            ),
            .wrapping(
                viewBlock: { [weak self] in
                    self?.buildResetButtonView()
                },
                margins: UIEdgeInsets(top: 12, leading: 32, bottom: 24, trailing: 32)
            )
        ])

        topSection.hasSeparators = false
        topSection.hasBackground = false

        linkCellSection.hasSeparators = false
        linkCellSection.hasBackground = true

        bottomSection.hasSeparators = false
        bottomSection.hasBackground = false

        defaultSpacingBetweenSections = 0
        contents = OWSTableContents(sections: [
            topSection,
            linkCellSection,
            bottomSection
        ])
    }

    // MARK: - Controller lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: CommonStrings.doneButton,
            style: .done,
            target: self,
            action: #selector(didTapDone),
            accessibilityIdentifier: "done"
        )
        navigationItem.title = OWSLocalizedString(
            "USERNAME_LINK_QR_CODE_VIEW_TITLE_CODE",
            comment: "A title for a view that allows you to view and interact with a QR code for your username link."
        )

        buildTableContents()
    }

    @objc
    private func didTapDone() {
        dismiss(animated: true)
    }
}

private extension OWSTableItem {
    private class ViewWrappingTableViewCell: UITableViewCell {
        init(viewToWrap: UIView, margins: UIEdgeInsets) {
            super.init(style: .default, reuseIdentifier: nil)

            selectionStyle = .none

            contentView.addSubview(viewToWrap)
            contentView.layoutMargins = margins

            viewToWrap.autoPinEdgesToSuperviewMargins()
        }

        required init?(coder: NSCoder) {
            owsFail("Not implemented!")
        }
    }

    static func wrapping(
        viewBlock: @escaping () -> UIView?,
        margins: UIEdgeInsets
    ) -> OWSTableItem {
        return OWSTableItem(customCellBlock: {
            guard let view = viewBlock() else {
                return UITableViewCell()
            }

            return ViewWrappingTableViewCell(
                viewToWrap: view,
                margins: margins
            )
        })
    }
}
