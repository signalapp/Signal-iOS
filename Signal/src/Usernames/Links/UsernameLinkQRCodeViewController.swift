//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalServiceKit
import SignalMessaging
import SignalUI

class UsernameLinkQRCodeViewController: OWSTableViewController2 {
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
        let color: UsernameLinkQRCodeColor
        let image: UIImage
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
        let currentQRCodeImage: UIImage? = currentQRCode?.image
        let currentQRCodeColor: UsernameLinkQRCodeColor = currentQRCode?.color ?? .grey

        let qrCodeView: QRCodeView = {
            let view = QRCodeView(useCircularWrapper: false)

            view.backgroundColor = .ows_white
            view.layer.borderWidth = 2
            view.layer.borderColor = currentQRCodeColor.border.cgColor
            view.layer.cornerRadius = 12
            view.layoutMargins = UIEdgeInsets(margin: 10)

            if let currentQRCodeImage {
                view.setQR(image: currentQRCodeImage)
            }

            return view
        }()

        let copyUsernameLabel: UILabel = {
            let label = UILabel()

            label.font = .dynamicTypeHeadline.semibold()
            label.numberOfLines = 0
            label.lineBreakMode = .byCharWrapping
            label.textColor = currentQRCodeColor.username
            label.text = usernameLink.username

            return label
        }()

        let copyUsernameView: UIView = {
            let copyImageView = UIImageView(image: Theme.iconImage(.buttonCopy))
            copyImageView.tintColor = currentQRCodeColor.username
            copyImageView.autoSetDimensions(to: .square(24))

            return CenteringStackView(centeredSubviews: [
                copyImageView,
                copyUsernameLabel
            ])
        }()

        let wrapperView = UIView()
        wrapperView.backgroundColor = currentQRCodeColor.background
        wrapperView.layer.cornerRadius = 24
        wrapperView.layoutMargins = UIEdgeInsets(hMargin: 40, vMargin: 32)

        wrapperView.addSubview(qrCodeView)
        wrapperView.addSubview(copyUsernameView)

        qrCodeView.autoPinTopToSuperviewMargin()
        qrCodeView.autoAlignAxis(toSuperviewAxis: .vertical)
        qrCodeView.autoSetDimension(.width, toSize: 214)

        qrCodeView.autoPinEdge(.bottom, to: .top, of: copyUsernameView, withOffset: -16)

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
            icon: .buttonShare,
            block: {
                // TODO: implement button
            }
        )

        let colorQRCodeButton = buildActionButton(
            text: OWSLocalizedString(
                "USERNAME_LINK_QR_CODE_VIEW_COLOR_BUTTON",
                comment: "Title for a button to pick the color of your username link QR code. Lowercase styling is intentional."
            ),
            icon: .chatSettingsWallpaper,
            block: { [weak self] in
                guard let self else { return }

                guard let currentQRCode = self.currentQRCode else {
                    owsFailDebug("Missing current QR code!")
                    return
                }

                let colorPickerVC = UsernameLinkQRCodeColorPickerViewController(
                    currentColor: currentQRCode.color,
                    username: self.usernameLink.username,
                    qrCodeImage: currentQRCode.image,
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
        let button = OWSButton(block: {
            // TODO: Implement button
        })

        button.setTitle(OWSLocalizedString(
            "USERNAME_LINK_QR_CODE_VIEW_RESET_BUTTON_TITLE",
            comment: "Title for a button that allows users to reset their username link and QR code."
        ), for: .normal)

        button.contentEdgeInsets = UIEdgeInsets(hMargin: 16, vMargin: 6)
        button.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_whiteAlpha70
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

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(didTapDone),
            accessibilityIdentifier: "done"
        )
        navigationItem.title = OWSLocalizedString(
            "USERNAME_LINK_QR_CODE_VIEW_TITLE_CODE",
            comment: "A title for a view that allows you to view and interact with a QR code for your username link."
        )

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

                guard let image = UsernameLinkQRCodeGenerator(color: color.foreground)
                    .generateQRCode(url: self.usernameLink.asUrl)
                else {
                    return
                }

                self.currentQRCode = QRCode(
                    color: color,
                    image: image
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

    @objc
    private func didTapDone() {
        dismiss(animated: true)
    }
}

extension UsernameLinkQRCodeViewController: UsernameLinkQRCodeColorPickerDelegate {
    func didFinalizeSelectedColor(color: UsernameLinkQRCodeColor) {
        guard let currentQRCode else {
            owsFail("How did we get here without a QR code?")
        }

        guard let newImage = currentQRCode.image.asTintedImage(
            color: color.foreground
        ) else {
            owsFailDebug("Failed to generate new tinted QR code!")
            return
        }

        db.write { tx in
            self.colorStore.set(color, tx: tx)
        }

        self.currentQRCode = QRCode(color: color, image: newImage)
        reloadTableContents()
    }
}
