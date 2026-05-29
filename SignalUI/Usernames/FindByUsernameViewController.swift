//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

protocol FindByUsernameDelegate: AnyObject {
    func findByUsername(address: SignalServiceAddress)
    var shouldShowQRCodeButton: Bool { get }
    func openQRCodeScanner()
}

enum FindByUsername {
    static func preParseUsername(_ userInput: String) -> String {
        return userInput.starts(with: "@") ? String(userInput.dropFirst()) : userInput
    }
}

public class FindByUsernameViewController: OWSTableViewController2 {

    weak var findByUsernameDelegate: FindByUsernameDelegate?

    private lazy var usernameTextField = OWSTextField(
        placeholder: OWSLocalizedString(
            "FIND_BY_USERNAME_PLACEHOLDER",
            comment: "A placeholder value for the text field for finding an account by their username",
        ),
        returnKeyType: .done,
        autocorrectionType: .no,
        autocapitalizationType: .none,
        editingChanged: { [weak self] in
            self?.textFieldDidChange()
        },
        returnPressed: { [weak self] in
            self?.didTapNext()
        },
    )

    private var usernameValue: String {
        let textValue = usernameTextField.text ?? ""
        return FindByUsername.preParseUsername(textValue)
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        updateTableContents()

        title = OWSLocalizedString(
            "FIND_BY_USERNAME_TITLE",
            comment: "Title for the view for finding accounts by their username",
        )

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: CommonStrings.nextButton,
            style: .done,
            target: self,
            action: #selector(didTapNext),
        )
        navigationItem.rightBarButtonItem?.isEnabled = false

        shouldAvoidKeyboard = true
    }

    override public func viewDidAppear(_ animated: Bool) {
        usernameTextField.becomeFirstResponder()
    }

    // MARK: Table contents

    private func updateTableContents() {
        let textField = self.usernameTextField
        let contents = OWSTableContents()
        defer {
            self.contents = contents
        }

        contents.add(OWSTableSection(
            title: nil,
            items: [
                .textFieldItem(textField),
            ],
            footerTitle: OWSLocalizedString(
                "FIND_BY_USERNAME_FOOTER",
                comment: "A footer below the username text field describing what should be entered",
            ),
        ))

        guard findByUsernameDelegate?.shouldShowQRCodeButton ?? false else {
            return
        }

        let qrButtonSection = OWSTableSection(items: [
            OWSTableItem(customCellBlock: { [weak self] in
                let cell = OWSTableItem.newCell()

                // Font taken from UIButton.Configuration.smallSecondary
                let buttonTitleFont = UIFont.dynamicTypeSubheadlineClamped.medium()
                var attributedButtonTitle = AttributedString(
                    SignalSymbol.qrcode.attributedString(
                        dynamicTypeBaseSize: buttonTitleFont.pointSize,
                    ),
                )
                attributedButtonTitle.append(AttributedString(" "))
                attributedButtonTitle.append(AttributedString(OWSLocalizedString(
                    "FIND_BY_USERNAME_SCAN_QR_CODE_BUTTON",
                    comment: "A button below the username text field which opens a username QR code scanner",
                )))
                var defaults = AttributeContainer()
                defaults.font = buttonTitleFont
                attributedButtonTitle.mergeAttributes(defaults, mergePolicy: .keepCurrent)

                let button = UIButton(
                    configuration: .smallSecondary(title: ""),
                    primaryAction: UIAction { [weak self] _ in
                        self?.findByUsernameDelegate?.openQRCodeScanner()
                    },
                )
                button.configuration?.titleTextAttributesTransformer = nil // otherwise `attributedTitle` won't work.
                button.configuration?.attributedTitle = attributedButtonTitle
                button.translatesAutoresizingMaskIntoConstraints = false
                cell.contentView.addSubview(button)
                NSLayoutConstraint.activate([
                    button.topAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.topAnchor),
                    button.leadingAnchor.constraint(greaterThanOrEqualTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                    button.centerXAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.centerXAnchor),
                    button.bottomAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.bottomAnchor),
                ])
                return cell
            }),
        ])
        qrButtonSection.hasBackground = false
        contents.add(qrButtonSection)
    }

    // MARK: Actions

    @objc
    private func textFieldDidChange() {
        do {
            _ = try Usernames.HashedUsername(forUsername: self.usernameValue)
            navigationItem.rightBarButtonItem?.isEnabled = true
        } catch {
            navigationItem.rightBarButtonItem?.isEnabled = false
        }
    }

    @objc
    private func didTapNext() {
        let usernameValue = self.usernameValue
        usernameTextField.resignFirstResponder()

        Task {
            guard
                let aci = await UsernameQuerier().queryForUsername(
                    username: usernameValue,
                    fromViewController: self,
                    failureSheetDismissalDelegate: self,
                )
            else {
                return
            }

            findByUsernameDelegate?.findByUsername(address: SignalServiceAddress(aci))
        }
    }
}

extension FindByUsernameViewController: SheetDismissalDelegate {
    public func didDismissPresentedSheet() {
        usernameTextField.becomeFirstResponder()
    }
}
