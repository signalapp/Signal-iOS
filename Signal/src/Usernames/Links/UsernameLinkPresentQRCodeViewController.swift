//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalServiceKit
import SignalMessaging
import SignalUI

class UsernameLinkPresentQRCodeViewController: OWSTableViewController2 {
    private struct ColorStore {
        static let key = "color"

        private let kvStore: KeyValueStore

        init(kvStoreFactory: KeyValueStoreFactory) {
            kvStore = kvStoreFactory.keyValueStore(collection: "UsernameLinkQRCode")
        }

        func get(tx: DBReadTransaction) -> UsernameLinkQRCodeColor? {
            do {
                return try kvStore.getCodableValue(forKey: Self.key, transaction: tx)
            } catch let error {
                owsFailDebug("Failed to load stored color! \(error)")
                return nil
            }
        }

        func set(_ color: UsernameLinkQRCodeColor, tx: DBWriteTransaction) {
            do {
                try kvStore.setCodable(color, key: Self.key, transaction: tx)
            } catch let error {
                owsFailDebug("Failed to store color! \(error)")
            }
        }
    }

    private struct QRCode {
        /// The color set to apply to the QR code image.
        let color: UsernameLinkQRCodeColor

        /// A template image for the QR code, for display.
        let displayImage: UIImage

        init(color: UsernameLinkQRCodeColor, displayImage: UIImage) {
            owsAssert(displayImage.renderingMode == .alwaysTemplate)

            self.color = color
            self.displayImage = displayImage
        }
    }

    private let db: DB
    private let colorStore: ColorStore

    private let usernameLink: Usernames.UsernameLink

    private var currentQRCode: QRCode?

    init(
        db: DB,
        kvStoreFactory: KeyValueStoreFactory,
        usernameLink: Usernames.UsernameLink
    ) {
        self.db = db
        self.colorStore = ColorStore(kvStoreFactory: kvStoreFactory)
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
        let qrCodeImage: UIImage? = currentQRCode?.displayImage
        let qrCodeColor: UsernameLinkQRCodeColor = currentQRCode?.color ?? .grey

        let qrCodeView: QRCodeView = {
            let view = QRCodeView(useCircularWrapper: false)

            view.backgroundColor = .ows_white
            view.layer.borderWidth = 2
            view.layer.borderColor = qrCodeColor.paddingBorder.cgColor
            view.layer.cornerRadius = 12
            view.layoutMargins = UIEdgeInsets(margin: 10)

            if let qrCodeImage {
                view.setQR(
                    templateImage: qrCodeImage,
                    tintColor: qrCodeColor.foreground
                )
            }

            return view
        }()

        let copyUsernameButton: UIButton = {
            let button = OWSButton(block: { [weak self] in
                guard let self else { return }

                UIPasteboard.general.string = self.usernameLink.username

                self.presentToast(text: OWSLocalizedString(
                    "USERNAME_LINK_QR_CODE_VIEW_USERNAME_COPIED",
                    comment: "Text presented in a toast notifying the user that their username was copied to the system clipboard."
                ))
            })

            button.setTitle(usernameLink.username, for: .normal)
            button.setTitleColor(qrCodeColor.username, for: .normal)
            button.titleLabel!.font = .dynamicTypeHeadline.semibold()

            button.setTemplateImage(
                Theme.iconImage(.buttonCopy),
                tintColor: qrCodeColor.username
            )

            button.imageView!.autoSetDimensions(to: .square(24))
            button.titleEdgeInsets = UIEdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 0)
            button.configureForMultilineTitle()

            button.dimsWhenHighlighted = true

            return button
        }()

        let wrapperView = UIView()
        wrapperView.backgroundColor = qrCodeColor.background
        wrapperView.layer.cornerRadius = 24
        wrapperView.layoutMargins = UIEdgeInsets(hMargin: 40, vMargin: 32)

        wrapperView.addSubview(qrCodeView)
        wrapperView.addSubview(copyUsernameButton)

        qrCodeView.autoPinTopToSuperviewMargin()
        qrCodeView.autoAlignAxis(toSuperviewAxis: .vertical)
        qrCodeView.autoSetDimension(.width, toSize: 214)

        qrCodeView.autoPinEdge(.bottom, to: .top, of: copyUsernameButton, withOffset: -16)

        copyUsernameButton.autoPinLeadingToSuperviewMargin()
        copyUsernameButton.autoPinTrailingToSuperviewMargin()
        copyUsernameButton.autoPinBottomToSuperviewMargin()

        return wrapperView
    }

    // MARK: Share and Color buttons

    private func buildActionButton(
        text: String,
        icon: ThemeIcon,
        block: @escaping (SettingsHeaderButton) -> Void
    ) -> SettingsHeaderButton {
        let button = SettingsHeaderButton(
            text: text,
            icon: icon,
            backgroundColor: OWSTableViewController2.cellBackgroundColor(
                isUsingPresentedStyle: true
            ),
            isEnabled: true,
            block: nil
        )

        button.block = { [weak button] in
            guard let button else { return }
            block(button)
        }

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
            icon: .buttonShare,
            block: { [weak self] actionButton in
                // Generate a color-over-white QR code and share. Show a modal
                // if it takes a while.

                guard let self else { return }

                guard let currentQRCodeColor = self.currentQRCode?.color else {
                    owsFailDebug("Missing current QR code color!")
                    return
                }

                ModalActivityIndicatorViewController.present(
                    fromViewController: self,
                    canCancel: true,
                    presentationDelay: 1
                ) { modal in
                    guard let qrCodeToShare = UsernameLinkQRCodeGenerator(
                        foregroundColor: currentQRCodeColor.foreground,
                        backgroundColor: .ows_white
                    ).generateQRCode(url: self.usernameLink.url) else {
                        modal.dismissIfNotCanceled()
                        return
                    }

                    modal.dismissIfNotCanceled {
                        ShareActivityUtil.present(
                            activityItems: [qrCodeToShare],
                            from: self,
                            sourceView: actionButton
                        )
                    }
                }
            }
        )

        let colorQRCodeButton = buildActionButton(
            text: OWSLocalizedString(
                "USERNAME_LINK_QR_CODE_VIEW_COLOR_BUTTON",
                comment: "Title for a button to pick the color of your username link QR code. Lowercase styling is intentional."
            ),
            icon: .chatSettingsWallpaper,
            block: { [weak self] _ in
                guard let self else { return }

                guard let currentQRCode = self.currentQRCode else {
                    owsFailDebug("Missing current QR code!")
                    return
                }

                let colorPickerVC = UsernameLinkQRCodeColorPickerViewController(
                    currentColor: currentQRCode.color,
                    username: self.usernameLink.username,
                    qrCodeTemplateImage: currentQRCode.displayImage,
                    delegate: self
                )

                self.presentFormSheet(
                    OWSNavigationController(rootViewController: colorPickerVC),
                    animated: true
                )
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
        let button = OWSRoundedButton(block: {
            // TODO: Implement button
        })

        button.setTitle(OWSLocalizedString(
            "USERNAME_LINK_QR_CODE_VIEW_RESET_BUTTON_TITLE",
            comment: "Title for a button that allows users to reset their username link and QR code."
        ), for: .normal)

        button.contentEdgeInsets = UIEdgeInsets(hMargin: 16, vMargin: 6)
        button.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_whiteAlpha70
        button.titleLabel!.font = .dynamicTypeBody2.bold()
        button.setTitleColor(Theme.primaryTextColor, for: .normal)

        button.configureForMultilineTitle()

        button.dimsWhenHighlighted = true

        return CenteringStackView(centeredSubviews: [button])
    }

    // MARK: Put it all together

    private func buildTableContents() {
        let topSection = OWSTableSection(items: [
            .itemWrappingView(
                viewBlock: { [weak self] in
                    return self?.buildQRCodeView()
                },
                margins: UIEdgeInsets(top: 32, leading: 48, bottom: 12, trailing: 48)
            ),
            .itemWrappingView(
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
                        itemName: self.usernameLink.url.absoluteString,
                        maxItemNameLines: 1,
                        accessoryType: .disclosureIndicator
                    )
                },
                actionBlock: { [weak self] in
                    guard let self else { return }

                    self.present(
                        UsernameLinkShareSheetViewController(usernameLink: self.usernameLink),
                        animated: true
                    )
                }
            )
        ])

        let bottomSection = OWSTableSection(items: [
            .itemWrappingView(
                viewBlock: { [weak self] in
                    self?.buildDisclaimerLabel()
                },
                margins: UIEdgeInsets(top: 28, leading: 32, bottom: 12, trailing: 32)
            ),
            .itemWrappingView(
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

        buildTableContents()
        loadQRCodeAndReloadTable()
    }

    /// Asynchronously load the QR code and reload the table view.
    ///
    /// These operations may be slow, and so we do them asynchronously off the
    /// main thread.
    private func loadQRCodeAndReloadTable() {
        owsAssert(
            currentQRCode == nil,
            "Current QR code was unexpectedly non-nil. How did something else set it?"
        )

        db.asyncRead(
            block: { tx in
                let color: UsernameLinkQRCodeColor = self.colorStore.get(tx: tx) ?? .blue

                // Generate a black-on-transparent image for now. We'll tint it
                // using the appropriate colors once it's in a view.
                guard let displayImage = UsernameLinkQRCodeGenerator(
                    foregroundColor: .ows_black,
                    backgroundColor: .clear
                ).generateQRCode(url: self.usernameLink.url) else {
                    return
                }

                self.currentQRCode = QRCode(
                    color: color,
                    displayImage: displayImage.withRenderingMode(.alwaysTemplate)
                )
            },
            completion: { [weak self] in
                guard let self, self.currentQRCode != nil else {
                    return
                }

                self.reloadTableContents()
            }
        )
    }

    private func reloadTableContents() {
        self.tableView.reloadData()
    }
}

extension UsernameLinkPresentQRCodeViewController: UsernameLinkQRCodeColorPickerDelegate {
    func didFinalizeSelectedColor(color: UsernameLinkQRCodeColor) {
        guard let currentQRCode else {
            owsFail("How did we get here without a QR code?")
        }

        db.write { tx in
            self.colorStore.set(color, tx: tx)
        }

        self.currentQRCode = QRCode(
            color: color,
            displayImage: currentQRCode.displayImage
        )
        reloadTableContents()
    }
}
