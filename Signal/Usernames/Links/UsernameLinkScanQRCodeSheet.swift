//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import SignalUI

class UsernameLinkScanQRCodeSheet: UsernameLinkScanQRCodeViewController {
    override var preferredNavigationBarStyle: OWSNavigationBarStyle { .solid }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = CommonStrings.scanQRCodeTitle
        navigationItem.rightBarButtonItem = .doneButton(dismissingFrom: self)
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

extension BaseMemberViewController: @retroactive MemberViewUsernameQRCodeScannerPresenter {
    public func presentUsernameQRCodeScannerFromMemberView() {
        presentUsernameQRCodeScanner()
    }
}

// MARK: UsernameLinkScanDelegate + RecipientPickerDelegate

extension BaseMemberViewController: UsernameLinkScanDelegate {}

extension UsernameLinkScanDelegate where Self: RecipientPickerDelegate & RecipientPickerContainerViewController {
    func usernameLinkScanned(_ usernameLink: Usernames.UsernameLink) {
        dismiss(animated: true) { [self] in
            Task { @MainActor in
                guard
                    let (_, aci) = await UsernameQuerier().queryForUsernameLink(
                        link: usernameLink,
                        fromViewController: self,
                    )
                else {
                    return
                }

                recipientPicker(
                    recipientPicker,
                    didSelectRecipient: .for(address: SignalServiceAddress(aci)),
                )
            }
        }
    }
}
