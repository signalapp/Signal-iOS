//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import SignalUI

class UsernameLinkScanQRCodeSheet: UsernameLinkScanQRCodeViewController {
    override var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = CommonStrings.scanQRCodeTitle
        navigationItem.leftBarButtonItem = .init(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(didTapDone)
        )
    }

    @objc
    private func didTapDone() {
        dismiss(animated: true)
    }
}

// MARK: RecipientPickerDelegate + UsernameLinkScanDelegate

extension RecipientPickerDelegate where Self: UIViewController & UsernameLinkScanDelegate {
    var shouldShowQRCodeButton: Bool { true }

    func openUsernameQRCodeScanner() {
        presentUsernameQRCodeScanner()
    }

    func presentUsernameQRCodeScanner() {
        let scanner = UsernameLinkScanQRCodeSheet(scanDelegate: self)
        let navigationController = OWSNavigationController(rootViewController: scanner)
        self.present(navigationController, animated: true)
    }
}

extension BaseMemberViewController: MemberViewUsernameQRCodeScannerPresenter, UsernameLinkScanDelegate {
    public func presentUsernameQRCodeScannerFromMemberView() {
        presentUsernameQRCodeScanner()
    }
}

// MARK: UsernameLinkScanDelegate + RecipientPickerDelegate

extension UsernameLinkScanDelegate where Self: RecipientPickerDelegate & RecipientPickerContainerViewController {
    func usernameLinkScanned(_ usernameLink: Usernames.UsernameLink) {
        dismiss(animated: true) {
            self.databaseStorage.read { tx in
                UsernameQuerier().queryForUsernameLink(
                    link: usernameLink,
                    fromViewController: self,
                    tx: tx
                ) { _, aci in
                    self.recipientPicker(
                        self.recipientPicker,
                        didSelectRecipient: .for(address: SignalServiceAddress(aci))
                    )
                }
            }
        }
    }
}
