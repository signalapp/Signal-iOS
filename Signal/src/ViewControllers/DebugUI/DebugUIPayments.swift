//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalMessaging

#if USE_DEBUG_UI

class DebugUIPayments: DebugUIPage {

    // MARK: Overrides 

    override func name() -> String {
        return "Payments"
    }

    override func section(thread: TSThread?) -> OWSTableSection? {
        var sectionItems = [OWSTableItem]()

        if let contactThread = thread as? TSContactThread {
            sectionItems.append(OWSTableItem(title: "Send payment request") { [weak self] in
                self?.sendPaymentRequestMessage(contactThread: contactThread)
            })
            sectionItems.append(OWSTableItem(title: "Send payment notification") { [weak self] in
                self?.sendPaymentNotificationMessage(contactThread: contactThread)
            })
            sectionItems.append(OWSTableItem(title: "Send payment cancellation") { [weak self] in
                self?.sendPaymentCancellationMessage(contactThread: contactThread)
            })
            sectionItems.append(OWSTableItem(title: "Send payment request + cancellation") { [weak self] in
                self?.sendPaymentRequestAndCancellation(contactThread: contactThread)
            })
            sectionItems.append(OWSTableItem(title: "Create all possible payment models") { [weak self] in
                self?.insertAllPaymentModelVariations(contactThread: contactThread)
            })
            sectionItems.append(OWSTableItem(title: "Send tiny payments: 10") {
                Self.sendTinyPayments(contactThread: contactThread, count: 10)
            })
            // For testing defragmentation.
            sectionItems.append(OWSTableItem(title: "Send tiny payments: 17") {
                Self.sendTinyPayments(contactThread: contactThread, count: 17)
            })
            // For testing defragmentation.
            sectionItems.append(OWSTableItem(title: "Send tiny payments: 40") {
                Self.sendTinyPayments(contactThread: contactThread, count: 40)
            })
            // For testing defragmentation.
            sectionItems.append(OWSTableItem(title: "Send tiny payments: 100") {
                Self.sendTinyPayments(contactThread: contactThread, count: 100)
            })
            sectionItems.append(OWSTableItem(title: "Send tiny payments: 1000") {
                Self.sendTinyPayments(contactThread: contactThread, count: 1000)
            })
        }

        sectionItems.append(OWSTableItem(title: "Delete all payment models") { [weak self] in
            self?.deleteAllPaymentModels()
        })
        sectionItems.append(OWSTableItem(title: "Reconcile now") {
            Self.databaseStorage.write { transaction in
                Self.payments.scheduleReconciliationNow(transaction: transaction)
            }
        })

        return OWSTableSection(title: "Payments", items: sectionItems)
    }

    private func sendPaymentRequestMessage(contactThread: TSContactThread) {
        let address = contactThread.contactAddress
        let picoMob = UInt64.random(in: 1..<256)
        let paymentAmount = TSPaymentAmount(currency: .mobileCoin,
                                            picoMob: picoMob)
        let memoMessage = "Please pay me because: \(UUID().uuidString)."
        firstly {
            PaymentsImpl.sendPaymentRequestMessagePromise(address: address,
                                                          paymentAmount: paymentAmount,
                                                          memoMessage: memoMessage)
        }.done { (_) -> Void in
            Logger.info("Success.")
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }

    private func sendPaymentNotificationMessage(contactThread: TSContactThread) {
        let address = contactThread.contactAddress
        // PAYMENTS TODO: Can we make this the right length?
        let mcReceiptData = Randomness.generateRandomBytes(1)
        let memoMessage = "I'm sending payment for: \(UUID().uuidString)."
        firstly {
            PaymentsImpl.sendPaymentNotificationMessagePromise(address: address,
                                                               memoMessage: memoMessage,
                                                               mcReceiptData: mcReceiptData,
                                                               requestUuidString: nil)
        }.done { (_) -> Void in
            Logger.info("Success.")
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }

    private func sendPaymentCancellationMessage(contactThread: TSContactThread) {
        let address = contactThread.contactAddress
        firstly { () -> Promise<OWSOutgoingPaymentMessage> in
            let requestUuidString = UUID().uuidString
            return PaymentsImpl.sendPaymentCancellationMessagePromise(address: address,
                                                                      requestUuidString: requestUuidString)
        }.done { (_) -> Void in
            Logger.info("Success.")
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }

    private func sendPaymentRequestAndCancellation(contactThread: TSContactThread) {
        let address = contactThread.contactAddress
        let picoMob = UInt64.random(in: 1..<256)
        let paymentAmount = TSPaymentAmount(currency: .mobileCoin,
                                            picoMob: picoMob)
        let memoMessage = "Please pay me because: \(UUID().uuidString)."
        firstly { () -> Promise<OWSOutgoingPaymentMessage> in
            PaymentsImpl.sendPaymentRequestMessagePromise(address: address,
                                                          paymentAmount: paymentAmount,
                                                          memoMessage: memoMessage)
        }.then { (requestMessage: OWSOutgoingPaymentMessage) -> Promise<OWSOutgoingPaymentMessage> in
            guard let requestUuidString = requestMessage.paymentRequest?.requestUuidString else {
                throw OWSAssertionError("Missing requestUuidString.")
            }
            return PaymentsImpl.sendPaymentCancellationMessagePromise(address: address,
                                                                      requestUuidString: requestUuidString)
        }.done { (_) -> Void in
            Logger.info("Success.")
        }.catch { error in
            owsFailDebug("Error: \(error)")
        }
    }

    private func insertAllPaymentModelVariations(contactThread: TSContactThread) {
        let address = contactThread.contactAddress
        let uuid = address.uuid!

        databaseStorage.write { transaction in
            let paymentAmounts = [
                TSPaymentAmount(currency: .mobileCoin, picoMob: 1),
                TSPaymentAmount(currency: .mobileCoin, picoMob: 1000),
                TSPaymentAmount(currency: .mobileCoin, picoMob: 1000 * 1000),
                TSPaymentAmount(currency: .mobileCoin, picoMob: 1000 * 1000 * 1000),
                TSPaymentAmount(currency: .mobileCoin, picoMob: 1000 * 1000 * 1000 * 1000),
                TSPaymentAmount(currency: .mobileCoin, picoMob: 1000 * 1000 * 1000 * 1000 * 1000)
            ]

            func insertPaymentModel(paymentType: TSPaymentType,
                                    paymentState: TSPaymentState) -> TSPaymentModel {
                let mcReceiptData = Randomness.generateRandomBytes(32)
                var mcTransactionData: Data?
                if paymentState.isIncoming {
                } else {
                    mcTransactionData = Randomness.generateRandomBytes(32)
                }
                var memoMessage: String?
                if Bool.random() {
                    memoMessage = "Pizza Party 🍕"
                }
                var addressUuidString: String?
                if !paymentType.isUnidentified {
                    addressUuidString = uuid.uuidString
                }
                // TODO: requestUuidString
                // TODO: isUnread
                // TODO: mcRecipientPublicAddressData
                // TODO: mobileCoin
                // TODO: feeAmount

                let mobileCoin = MobileCoinPayment(recipientPublicAddressData: nil,
                                                   transactionData: mcTransactionData,
                                                   receiptData: mcReceiptData,
                                                   incomingTransactionPublicKeys: nil,
                                                   spentKeyImages: nil,
                                                   outputPublicKeys: nil,
                                                   ledgerBlockTimestamp: 0,
                                                   ledgerBlockIndex: 0,
                                                   feeAmount: nil)

                let paymentModel = TSPaymentModel(paymentType: paymentType,
                                                  paymentState: paymentState,
                                                  paymentAmount: paymentAmounts.randomElement()!,
                                                  createdDate: Date(),
                                                  addressUuidString: addressUuidString,
                                                  memoMessage: memoMessage,
                                                  requestUuidString: nil,
                                                  isUnread: false,
                                                  mobileCoin: mobileCoin)
                do {
                    try Self.paymentsHelper.tryToInsertPaymentModel(paymentModel, transaction: transaction)
                } catch {
                    owsFailDebug("Error: \(error)")
                }
                return paymentModel
            }

            var paymentModel: TSPaymentModel

            // MARK: - Incoming

            paymentModel = insertPaymentModel(paymentType: .incomingPayment, paymentState: .incomingUnverified)
            paymentModel = insertPaymentModel(paymentType: .incomingPayment, paymentState: .incomingVerified)
            paymentModel = insertPaymentModel(paymentType: .incomingPayment, paymentState: .incomingComplete)

            // MARK: - Outgoing

            paymentModel = insertPaymentModel(paymentType: .outgoingPayment, paymentState: .outgoingUnsubmitted)
            paymentModel = insertPaymentModel(paymentType: .outgoingPayment, paymentState: .outgoingUnverified)
            paymentModel = insertPaymentModel(paymentType: .outgoingPayment, paymentState: .outgoingVerified)
            paymentModel = insertPaymentModel(paymentType: .outgoingPayment, paymentState: .outgoingSending)
            paymentModel = insertPaymentModel(paymentType: .outgoingPayment, paymentState: .outgoingSent)
            paymentModel = insertPaymentModel(paymentType: .outgoingPayment, paymentState: .outgoingComplete)

            // MARK: - Failures

            // TODO: We probably don't want to create .none and .unknown
//            paymentModel = insertPaymentModel(paymentState: .outgoingFailed)
//            paymentModel.update(withPaymentFailure: .none,
//                                paymentState: .outgoingFailed,
//                                transaction: transaction)
//
//            paymentModel = insertPaymentModel(paymentState: .incomingFailed)
//            paymentModel.update(withPaymentFailure: .none,
//                                paymentState: .incomingFailed,
//                                transaction: transaction)
//
//            paymentModel = insertPaymentModel(paymentState: .outgoingFailed)
//            paymentModel.update(withPaymentFailure: .unknown,
//                                paymentState: .outgoingFailed,
//                                transaction: transaction)
//
//            paymentModel = insertPaymentModel(paymentState: .incomingFailed)
//            paymentModel.update(withPaymentFailure: .unknown,
//                                paymentState: .incomingFailed,
//                                transaction: transaction)

            paymentModel = insertPaymentModel(paymentType: .outgoingPayment, paymentState: .outgoingFailed)
            paymentModel.update(withPaymentFailure: .insufficientFunds,
                                paymentState: .outgoingFailed,
                                transaction: transaction)

            paymentModel = insertPaymentModel(paymentType: .outgoingPayment, paymentState: .outgoingFailed)
            paymentModel.update(withPaymentFailure: .validationFailed,
                                paymentState: .outgoingFailed,
                                transaction: transaction)

            paymentModel = insertPaymentModel(paymentType: .incomingPayment, paymentState: .incomingFailed)
            paymentModel.update(withPaymentFailure: .validationFailed,
                                paymentState: .incomingFailed,
                                transaction: transaction)

            paymentModel = insertPaymentModel(paymentType: .outgoingPayment, paymentState: .outgoingFailed)
            paymentModel.update(withPaymentFailure: .notificationSendFailed,
                                paymentState: .outgoingFailed,
                                transaction: transaction)

            paymentModel = insertPaymentModel(paymentType: .incomingPayment, paymentState: .incomingFailed)
            paymentModel.update(withPaymentFailure: .invalid,
                                paymentState: .incomingFailed,
                                transaction: transaction)

            paymentModel = insertPaymentModel(paymentType: .outgoingPayment, paymentState: .outgoingFailed)
            paymentModel.update(withPaymentFailure: .invalid,
                                paymentState: .outgoingFailed,
                                transaction: transaction)

            // MARK: - Unidentified

            paymentModel = insertPaymentModel(paymentType: .incomingUnidentified, paymentState: .incomingComplete)
            paymentModel = insertPaymentModel(paymentType: .outgoingUnidentified, paymentState: .outgoingComplete)
        }
    }

    private static func sendTinyPayments(contactThread: TSContactThread, count: UInt) {
        let picoMob = PaymentsConstants.picoMobPerMob + UInt64.random(in: 0..<1000)
        let paymentAmount = TSPaymentAmount(currency: .mobileCoin, picoMob: picoMob)
        let recipient = SendPaymentRecipientImpl.address(address: contactThread .contactAddress)
        firstly(on: DispatchQueue.global()) { () -> Promise<PreparedPayment> in
            Self.paymentsImpl.prepareOutgoingPayment(recipient: recipient,
                                                     paymentAmount: paymentAmount,
                                                     memoMessage: "Tiny: \(count)",
                                                     paymentRequestModel: nil,
                                                     isOutgoingTransfer: false,
                                                     canDefragment: false)
        }.then(on: DispatchQueue.global()) { (preparedPayment: PreparedPayment) in
            Self.paymentsImpl.initiateOutgoingPayment(preparedPayment: preparedPayment)
        }.then(on: DispatchQueue.global()) { (paymentModel: TSPaymentModel) in
            Self.paymentsImpl.blockOnOutgoingVerification(paymentModel: paymentModel)
        }.done(on: DispatchQueue.global()) { _ in
            if count > 1 {
                Self.sendTinyPayments(contactThread: contactThread, count: count - 1)
            } else {
                Logger.info("Complete.")
            }
        }.catch(on: DispatchQueue.global()) { error in
            owsFailDebug("Error: \(error)")
        }
    }

    private func deleteAllPaymentModels() {
        databaseStorage.write { transaction in
            TSPaymentModel.anyRemoveAllWithInstantation(transaction: transaction)
        }
    }
}

#endif
