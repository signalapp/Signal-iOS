//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalMessaging

protocol FindByUsernameDelegate: AnyObject {
    func findByUsername(address: SignalServiceAddress)
}

public class FindByUsernameViewController: OWSTableViewController2 {

    weak var findByUsernameDelegate: FindByUsernameDelegate?

    private lazy var usernameTextField: OWSTextField = {
        let textField = OWSTextField()
        textField.returnKeyType = .done
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.placeholder = OWSLocalizedString(
            "FIND_BY_USERNAME_PLACEHOLDER",
            comment: "A placeholder value for the text field for finding an account by their username"
        )
        textField.addTarget(self, action: #selector(textFieldDidChange), for: .editingChanged)
        textField.addTarget(self, action: #selector(didTapNext), for: .editingDidEndOnExit)
        return textField
    }()

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

    private func updateTableContents() {
        let textField = self.usernameTextField
        self.contents = OWSTableContents(sections: [
            OWSTableSection(
                title: nil,
                items: [
                    OWSTableItem(customCellBlock: {
                        let cell = OWSTableItem.newCell()
                        cell.selectionStyle = .none
                        cell.addSubview(textField)
                        textField.autoPinEdgesToSuperviewMargins()
                        textField.font = .dynamicTypeBody
                        textField.textColor = Theme.primaryTextColor
                        return cell
                    }, actionBlock: {
                        textField.becomeFirstResponder()
                    })
                ],
                footerTitle: OWSLocalizedString(
                    "FIND_BY_USERNAME_FOOTER",
                    comment: "A footer below the username text field describing what should be entered"
                )
            )
        ])
    }

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
        databaseStorage.read { tx in
            UsernameQuerier().queryForUsername(
                username: username,
                fromViewController: self,
                tx: tx,
                onSuccess: { [weak self] aci in
                    AssertIsOnMainThread()
                    self?.findByUsernameDelegate?.findByUsername(address: SignalServiceAddress(aci))
                }
            )
        }
    }

}
