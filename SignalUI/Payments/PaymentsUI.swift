//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

@objc
public class PaymentsUI: NSObject {
}

// MARK: -

@objc
public extension PaymentsUI {

    static func declinePaymentRequest(paymentRequestModel: TSPaymentRequestModel,
                                      fromViewController: UIViewController) {
        AssertIsOnMainThread()

        let userName = databaseStorage.write { transaction -> String in
            let contactThread = TSContactThread.getOrCreateThread(withContactAddress: paymentRequestModel.address,
                                                                        transaction: transaction)
            return Self.contactsManager.displayName(for: contactThread.contactAddress,
                                                    transaction: transaction)

        }

        let title = OWSLocalizedString("PAYMENTS_DECLINE_REQUEST_ALERT_TITLE",
                                      comment: "Title for the 'decline a payment request' alert.")
        let messageFormat = OWSLocalizedString("PAYMENTS_DECLINE_REQUEST_ALERT_MESSAGE_FORMAT",
                                      comment: "Message for the 'decline a payment request' alert. Embeds {{ the name of the user requesting payment }}.")
        let alertMessage = String(format: messageFormat, userName)
        let actionSheet = ActionSheetController(title: title, message: alertMessage)
        actionSheet.addAction(ActionSheetAction(
                                title: OWSLocalizedString("PAYMENTS_ACTION_DECLINE_REQUEST",
                                                         comment: "Button used to decline a payment request."),
            style: .default,
            handler: { [weak fromViewController] _ in
                guard let fromViewController = fromViewController else {
                    return
                }
                Self.declinePaymentRequestConfirmed(paymentRequestModel: paymentRequestModel,
                                                    fromViewController: fromViewController)
            }
        ))
        actionSheet.addAction(OWSActionSheets.cancelAction)
        fromViewController.presentActionSheet(actionSheet)
    }

    private static func declinePaymentRequestConfirmed(paymentRequestModel: TSPaymentRequestModel,
                                                       fromViewController: UIViewController) {
        AssertIsOnMainThread()

        ModalActivityIndicatorViewController.present(fromViewController: fromViewController,
                                                     canCancel: false) { modalActivityIndicator in
            firstly(on: .global()) {
                declinePaymentRequestPromise(paymentRequestModel: paymentRequestModel)
            }.done(on: .main) { _ in
                modalActivityIndicator.dismiss()
            }.catch { error in
                owsFailDebug("Error: \(error)")

                modalActivityIndicator.dismiss {
                    OWSActionSheets.showErrorAlert(message: OWSLocalizedString("PAYMENTS_ERROR_PAYMENT_REQUEST_DECLINE_FAILED",
                                                                              comment: "Error indicating that a payment request could not be declined."))
                }
            }
        }
    }

    // PAYMENTS TODO: Move to PaymentsImpl?
    @nonobjc
    private static func declinePaymentRequestPromise(paymentRequestModel: TSPaymentRequestModel) -> Promise<Void> {
        firstly(on: .global()) { () -> Void in
            try Self.databaseStorage.write { transaction in
                // Pull latest model from db; ensure it still exists in db.
                guard let paymentRequestModel = TSPaymentRequestModel.anyFetch(uniqueId: paymentRequestModel.uniqueId,
                                                                               transaction: transaction) else {
                    // This race should be extremely unlikely.
                    throw OWSAssertionError("paymentRequestModel not found.")
                }
                guard paymentRequestModel.isValid else {
                    throw OWSAssertionError("Invalid paymentRequestModel.")
                }
                guard paymentRequestModel.isIncomingRequest else {
                    throw OWSAssertionError("Invalid paymentType.")
                }
                let contactAddress = paymentRequestModel.address
                let requestUuidString = paymentRequestModel.requestUuidString
                _ = PaymentsImpl.sendPaymentCancellationMessage(address: contactAddress,
                                                                requestUuidString: requestUuidString,
                                                                transaction: transaction)

                paymentRequestModel.anyRemove(transaction: transaction)
            }
        }
    }

    static func cancelPaymentRequest(paymentRequestModel: TSPaymentRequestModel,
                                     fromViewController: UIViewController) {
        AssertIsOnMainThread()

        ModalActivityIndicatorViewController.present(fromViewController: fromViewController,
                                                     canCancel: false) { modalActivityIndicator in
            firstly(on: .global()) {
                cancelPaymentRequestPromise(paymentRequestModel: paymentRequestModel)
            }.done(on: .main) { _ in
                modalActivityIndicator.dismiss()
            }.catch { error in
                owsFailDebug("Error: \(error)")

                modalActivityIndicator.dismiss {
                    OWSActionSheets.showErrorAlert(message: OWSLocalizedString("PAYMENTS_ERROR_PAYMENT_REQUEST_CANCEL_FAILED",
                                                                              comment: "Error indicating that a payment request could not be cancelled."))
                }
            }
        }
    }

    // PAYMENTS TODO: Move to PaymentsImpl?
    @nonobjc
    private static func cancelPaymentRequestPromise(paymentRequestModel: TSPaymentRequestModel) -> Promise<Void> {
        firstly(on: .global()) { () -> Void in
            try Self.databaseStorage.write { transaction in
                // Pull latest model from db; ensure it still exists in db.
                guard let paymentRequestModel = TSPaymentRequestModel.anyFetch(uniqueId: paymentRequestModel.uniqueId,
                                                                               transaction: transaction) else {
                    // This race should be extremely unlikely.
                    throw OWSAssertionError("paymentRequestModel not found.")
                }
                guard paymentRequestModel.isValid else {
                    throw OWSAssertionError("Invalid paymentRequestModel.")
                }
                guard paymentRequestModel.isIncomingRequest else {
                    throw OWSAssertionError("Invalid paymentType.")
                }
                let contactAddress = paymentRequestModel.address
                let requestUuidString = paymentRequestModel.requestUuidString
                _ = PaymentsImpl.sendPaymentCancellationMessage(address: contactAddress,
                                                                requestUuidString: requestUuidString,
                                                                transaction: transaction)

                paymentRequestModel.anyRemove(transaction: transaction)
            }
        }
    }
}
