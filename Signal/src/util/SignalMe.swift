//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
class SignalMe: NSObject {
    private static let pattern = try! NSRegularExpression(pattern: "^(?:https|\(kURLSchemeSGNLKey))://signal.me/#p/(\\+[0-9]+)$", options: [])

    @objc
    static func isPossibleUrl(_ url: URL) -> Bool {
        pattern.hasMatch(input: url.absoluteString.lowercased())
    }

    @objc
    static func openChat(url: URL, fromViewController: UIViewController) {
        open(url: url, fromViewController: fromViewController) {
            AssertIsOnMainThread()
            signalApp.presentConversation(for: $0, action: .compose, animated: true)
        }
    }

    private static func open(url: URL, fromViewController: UIViewController, block: @escaping (SignalServiceAddress) -> Void) {
        guard let phoneNumber = pattern.parseFirstMatch(inText: url.absoluteString.lowercased()) else { return }

        ModalActivityIndicatorViewController.present(fromViewController: fromViewController, canCancel: true) { modal in
            firstly(on: .sharedUserInitiated) { () -> Promise<SignalRecipient?> in
                let existingRecipient = databaseStorage.read { transaction in
                    AnySignalRecipientFinder().signalRecipientForPhoneNumber(phoneNumber, transaction: transaction)
                }
                if let existingRecipient = existingRecipient, existingRecipient.devices.count > 0 {
                    return Promise.value(existingRecipient)
                }

                return ContactDiscoveryTask(phoneNumbers: [phoneNumber]).perform(at: .userInitiated).map { $0.first }
            }.done(on: .main) { recipient in
                AssertIsOnMainThread()

                guard !modal.wasCancelled else { return }

                modal.dismiss {
                    guard let recipient = recipient else {
                        return OWSActionSheets.showErrorAlert(message: MessageSenderNoSuchSignalRecipientError().userErrorDescription)
                    }

                    block(recipient.address)
                }
            }.catch(on: .main) { error in
                AssertIsOnMainThread()
                guard !modal.wasCancelled else { return }

                modal.dismiss {
                    OWSActionSheets.showErrorAlert(message: error.userErrorDescription)
                }
            }
        }
    }
}
