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

public class FindByUsernameViewController: OWSTableViewController2 {

    weak var findByUsernameDelegate: FindByUsernameDelegate?

    private lazy var usernameTextField = OWSTextField(
        placeholder: OWSLocalizedString(
            "FIND_BY_USERNAME_PLACEHOLDER",
            comment: "A placeholder value for the text field for finding an account by their username"
        ),
        returnKeyType: .done,
        autocorrectionType: .no,
        autocapitalizationType: .none,
        editingChanged: { [weak self] in
            self?.textFieldDidChange()
        },
        returnPressed: { [weak self] in
            self?.didTapNext()
        }
    )

    public override func viewDidLoad() {
        super.viewDidLoad()
        updateTableContents()

        title = OWSLocalizedString(
            "FIND_BY_USERNAME_TITLE",
            comment: "Title for the view for finding accounts by their username"
        )

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: CommonStrings.nextButton,
            style: .done,
            target: self,
            action: #selector(didTapNext)
        )
        navigationItem.rightBarButtonItem?.isEnabled = false
    }

    public override func viewDidAppear(_ animated: Bool) {
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
                comment: "A footer below the username text field describing what should be entered"
            )
        ))

        guard findByUsernameDelegate?.shouldShowQRCodeButton ?? false else {
            return
        }

        let qrButtonSection = OWSTableSection(items: [
            OWSTableItem(customCellBlock: { [weak self] in
                let cell = OWSTableItem.newCell()
                let button = OWSRoundedButton {
                    self?.findByUsernameDelegate?.openQRCodeScanner()
                }
                let font = UIFont.dynamicTypeSubheadline
                let title = NSAttributedString.composed(of: [
                    NSAttributedString.with(image: Theme.iconImage(.qrCode), font: font),
                    " ",
                    OWSLocalizedString(
                        "FIND_BY_USERNAME_SCAN_QR_CODE_BUTTON",
                        comment: "A button below the username text field which opens a username QR code scanner"
                    )
                ]).styled(
                    with: .font(font.medium()),
                    .color(Theme.primaryTextColor)
                )
                button.setAttributedTitle(title, for: .normal)
                button.backgroundColor = Theme.tableCell2PresentedBackgroundColor
                button.dimsWhenHighlighted = true
                button.ows_contentEdgeInsets = .init(hMargin: 16, vMargin: 6)
                cell.addSubview(button)
                button.autoPinEdge(toSuperviewMargin: .top)
                button.autoPinEdge(toSuperviewMargin: .bottom)
                button.autoCenterInSuperviewMargins()
                button.autoPinEdge(toSuperviewMargin: .leading, relation: .greaterThanOrEqual)
                button.autoPinEdge(toSuperviewMargin: .trailing, relation: .greaterThanOrEqual)
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
            _ = try Usernames.HashedUsername(forUsername: usernameTextField.text ?? "")
            navigationItem.rightBarButtonItem?.isEnabled = true
        } catch {
            navigationItem.rightBarButtonItem?.isEnabled = false
        }
    }

    @objc
    private func didTapNext() {
        guard let username = usernameTextField.text else { return }
        usernameTextField.resignFirstResponder()
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            UsernameQuerier().queryForUsername(
                username: username,
                fromViewController: self,
                tx: tx,
                failureSheetDismissalDelegate: self,
                onSuccess: { [weak self] aci in
                    AssertIsOnMainThread()
                    self?.findByUsernameDelegate?.findByUsername(address: SignalServiceAddress(aci))
                }
            )
        }
    }

}

extension FindByUsernameViewController: SheetDismissalDelegate {
    public func didDismissPresentedSheet() {
        usernameTextField.becomeFirstResponder()
    }
}
