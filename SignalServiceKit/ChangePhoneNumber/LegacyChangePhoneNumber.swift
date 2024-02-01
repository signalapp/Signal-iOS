//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalCoreKit

@objc
public class LegacyChangePhoneNumber: NSObject {

    private let changePhoneNumberPniManager: ChangePhoneNumberPniManager

    /// Records change-number operations that were started (by this, or
    /// potentially a prior launch of the app) but not yet known to have
    /// completed.
    ///
    /// If, on a launch, we find an incomplete change-number operation in here,
    /// we will attempt to recover it.
    private let incompleteChangeTokenStore = IncompleteChangeTokenStore()

    @objc
    public override init() {
        self.changePhoneNumberPniManager = DependenciesBridge.shared.changePhoneNumberPniManager

        super.init()

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.recoverInterruptedChangeNumberIfNecessary()
        }
    }

    /// Parameters representing a successfully-completed change.
    public struct SuccessfulChangeParams {
        /// Our account's new E164 on the service.
        let newServiceE164: E164
        /// Our account's ACI on the service.
        let serviceAci: Aci
        /// Our account's PNI on the service.
        let servicePni: Pni

        public init(
            newServiceE164: E164,
            serviceAci: Aci,
            servicePni: Pni
        ) {
            self.newServiceE164 = newServiceE164
            self.serviceAci = serviceAci
            self.servicePni = servicePni
        }
    }

    /// Mark the given change as complete, optionally including additional data
    /// if the change was completed successfully.
    ///
    /// - Parameter changeToken
    /// The change to mark as complete.
    /// - Parameter successfulChange
    /// If the change was successful, contains parameters representing our new
    /// state post-change. `nil` if the change was unsuccessful.
    public func changeDidComplete(
        changeToken: ChangeToken,
        successfulChangeParams: SuccessfulChangeParams?,
        transaction: SDSAnyWriteTransaction
    ) {
        owsAssertDebug(CurrentAppContext().isMainApp)

        if let successfulChangeParams {
            do {
                try updateLocalPhoneNumber(
                    forServiceAci: successfulChangeParams.serviceAci,
                    servicePni: successfulChangeParams.servicePni,
                    serviceE164: successfulChangeParams.newServiceE164,
                    transaction: transaction
                )
            } catch {
                Logger.error("Failed to update local state while completing change!")
            }
        }

        incompleteChangeTokenStore.clear(
            changeToken: changeToken,
            transaction: transaction
        )
    }

    /// Take steps to recover from an interrupted change-number operation,
    /// indicated by the presence of the given change token.
    private func recoverIncompleteChangeToken(
        changeToken: ChangeToken
    ) -> Promise<Void> {
        firstly { () -> Promise<WhoAmIRequestFactory.Responses.WhoAmI> in
            self.accountServiceClient.getAccountWhoAmI()
        }.done(on: DispatchQueue.global()) { whoAmIResponse in
            self.databaseStorage.write { transaction in
                let successfulChangeParams = SuccessfulChangeParams(
                    newServiceE164: whoAmIResponse.e164,
                    serviceAci: whoAmIResponse.aci,
                    servicePni: whoAmIResponse.pni
                )

                self.changeDidComplete(
                    changeToken: changeToken,
                    successfulChangeParams: successfulChangeParams,
                    transaction: transaction
                )
            }
        }.recover(on: DispatchQueue.global()) { error in
            if error.isNetworkFailureOrTimeout {
                // If there was a network error, we can't confirm anything.
                throw error
            }

            self.databaseStorage.write { transaction in
                self.changeDidComplete(
                    changeToken: changeToken,
                    successfulChangeParams: nil,
                    transaction: transaction
                )
            }
        }
    }

    private func recoverInterruptedChangeNumberIfNecessary() {
        guard AppReadiness.isAppReady else {
            owsFailDebug("isAppReady.")
            return
        }

        if DependenciesBridge.shared.appExpiry.isExpired {
            owsFailDebug("appExpiry.")
            return
        }

        guard
            CurrentAppContext().isMainApp,
            DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
        else {
            return
        }

        let incompleteChangeToken: ChangeToken? = self.databaseStorage.read { transaction in
            incompleteChangeTokenStore.existingToken(
                transaction: transaction
            )
        }

        guard let incompleteChangeToken else {
            return
        }

        firstly { () -> Promise<Void> in
            recoverIncompleteChangeToken(
                changeToken: incompleteChangeToken
            )
        }.done(on: DispatchQueue.global()) {
            Logger.info("Recovered incomplete change token!")
        }.catch(on: DispatchQueue.global()) { error in
            Logger.info("Failed to recover incomplete change token: \(error)")
        }
    }

    // MARK: - Update the local phone number

    /// Warning: do not use this method.
    ///
    /// In a PNI world, it's not safe to update the E164 based on a WhoAmI
    /// request (which this does), since the E164 is semantically linked to
    /// data not available in the WhoAmI (such as the PNI identity key).
    ///
    /// This method exists to preserve existing behavior in an error scenario
    /// we should never find ourselves in. When we remove the E164 from the
    /// StorageService AccountRecord, we should remove this behavior as well.
    @objc
    public func deprecated_updateLocalPhoneNumberOnAccountRecordMismatch() {
        // PNP0 TODO: Remove this once we've removed the e164 from AccountRecord.

        firstly { () -> Promise<WhoAmIRequestFactory.Responses.WhoAmI> in
            Self.accountServiceClient.getAccountWhoAmI()
        }.map(on: DispatchQueue.global()) { whoAmIResponse throws in
            try self.databaseStorage.write { transaction in
                try self.updateLocalPhoneNumber(
                    forServiceAci: whoAmIResponse.aci,
                    servicePni: whoAmIResponse.pni,
                    serviceE164: whoAmIResponse.e164,
                    transaction: transaction
                )
            }
        }.catch(on: DispatchQueue.global()) { error in
            owsFailDebugUnlessNetworkFailure(error)
        }
    }

    /// Update local state concerning the phone number, based on values fetched
    /// from the service.
    /// 
    /// - Returns
    /// The persisted local phone number.
    @discardableResult
    fileprivate func updateLocalPhoneNumber(
        forServiceAci serviceAci: Aci,
        servicePni: Pni,
        serviceE164: E164,
        transaction: SDSAnyWriteTransaction
    ) throws -> E164 {
        guard
            let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read),
            let localE164 = E164(localIdentifiers.phoneNumber)
        else {
            throw OWSAssertionError("Missing or invalid local parameters!")
        }

        let localAci = localIdentifiers.aci
        let localPni = localIdentifiers.pni

        guard serviceAci == localAci else {
            throw OWSAssertionError("Service ACI \(serviceAci) unexpectedly did not match local ACI!")
        }

        Logger.info(
            """
            localAci: \(localAci),
            localPni: \(localPni?.logString ?? "nil"),
            localE164: \(localE164),
            serviceAci: \(serviceAci),
            servicePni: \(servicePni),
            serviceE164: \(serviceE164)")
            """
        )

        let recipientMerger = DependenciesBridge.shared.recipientMerger
        let localRecipient = recipientMerger.applyMergeForLocalAccount(
            aci: serviceAci,
            phoneNumber: serviceE164,
            pni: servicePni,
            tx: transaction.asV2Write
        )
        let recipientManager = DependenciesBridge.shared.recipientManager
        recipientManager.markAsRegisteredAndSave(localRecipient, shouldUpdateStorageService: false, tx: transaction.asV2Write)

        if
            serviceE164 != localE164
                || servicePni != localPni
        {
            Logger.info(
                "Recording new phone number: \(serviceE164), PNI: \(servicePni)"
            )

            DependenciesBridge.shared.registrationStateChangeManager.didUpdateLocalPhoneNumber(
                serviceE164,
                aci: serviceAci,
                pni: servicePni,
                tx: transaction.asV2Write
            )

            self.storageServiceManager.recordPendingLocalAccountUpdates()

            return serviceE164
        } else {
            return localE164
        }
    }
}
