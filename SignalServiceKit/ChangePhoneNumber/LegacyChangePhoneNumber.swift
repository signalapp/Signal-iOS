//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

@objc
public class LegacyChangePhoneNumber: NSObject {

    private enum Constants {
        static let localUserSupportsChangePhoneNumberKey = "localUserSupportsChangePhoneNumber"
    }

    private let changePhoneNumberPniManager: ChangePhoneNumberPniManager

    /// Stores metadata about change-number operations for this user.
    private let keyValueStore = SDSKeyValueStore(collection: "ChangePhoneNumber")

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

    public func deprecated_buildNewChangeToken(
        forNewE164 newE164: E164,
        transaction synchronousTransaction: SDSAnyWriteTransaction
    ) -> Promise<(ChangePhoneNumberPni.Parameters, ChangeToken)> {
        typealias Parameters = ChangePhoneNumberPni.Parameters
        typealias PendingState = ChangePhoneNumberPni.PendingState

        owsAssertDebug(CurrentAppContext().isMainApp)

        return firstly { () -> Promise<(Parameters, PendingState)> in
            func makeGeneratePniIdentityPromise(
                usingTransaction transaction: SDSAnyWriteTransaction
            ) -> Promise<(Parameters, PendingState)> {
                guard
                    let localAci = tsAccountManager.localUuid(with: transaction).map({ ServiceId($0) }),
                    let localAddress = tsAccountManager.localAddress(with: transaction),
                    let localRecipient = SignalRecipient.get(
                        address: localAddress,
                        mustHaveDevices: false,
                        transaction: transaction
                    ),
                    let localUserAllDeviceIds = localRecipient.deviceIds
                else {
                    return .init(error: OWSAssertionError("Missing local parameters!"))
                }

                return changePhoneNumberPniManager.generatePniIdentity(
                    forNewE164: newE164,
                    localAci: localAci,
                    localAccountId: localRecipient.accountId,
                    localDeviceId: tsAccountManager.storedDeviceId(transaction: transaction),
                    localUserAllDeviceIds: localUserAllDeviceIds
                ).then(on: DispatchQueue.global()) { generatePniIdentityResult -> Promise<(Parameters, PendingState)> in
                    switch generatePniIdentityResult {
                    case let .success(parameters, pendingState):
                        return .value((parameters, pendingState))
                    case .failure:
                        return .init(error: OWSAssertionError("Failed to generate PNI identity!"))
                    }
                }
            }

            // If we have an incomplete change token from a previous
            // interrupted attempt, attempt to recover that before proceeding
            // with PNI identity generation.

            let incompleteChangeToken: ChangeToken? = incompleteChangeTokenStore.existingToken(
                transaction: synchronousTransaction
            )

            if let incompleteChangeToken {
                return firstly { () -> Promise<Void> in
                    recoverIncompleteChangeToken(
                        changeToken: incompleteChangeToken
                    )
                }.then(on: DispatchQueue.global()) { () -> Promise<(Parameters, PendingState)> in
                    self.databaseStorage.write { transaction in
                        makeGeneratePniIdentityPromise(usingTransaction: transaction)
                    }
                }
            } else {
                return makeGeneratePniIdentityPromise(usingTransaction: synchronousTransaction)
            }
        }.map(on: DispatchQueue.global()) { (parameters, pendingState) throws -> (Parameters, ChangeToken) in
            let newChangeToken: ChangeToken = {
                return ChangeToken(legacyChangeId: UUID().uuidString)
            }()

            try self.databaseStorage.write { transaction in
                try self.incompleteChangeTokenStore.save(
                    changeToken: newChangeToken,
                    transaction: transaction
                )
            }

            return (parameters, newChangeToken)
        }
    }

    /// Parameters representing a successfully-completed change.
    public struct SuccessfulChangeParams {
        /// Our account's new E164 on the service.
        let newServiceE164: E164
        /// Our account's ACI on the service.
        let serviceAci: UUID
        /// Our account's PNI on the service.
        let servicePni: UUID

        public init(
            newServiceE164: E164,
            serviceAci: UUID,
            servicePni: UUID
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
            tsAccountManager.isRegisteredAndReady
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
        // PNI TODO: Remove this once we've removed the e164 from AccountRecord.

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
        forServiceAci serviceAci: UUID,
        servicePni: UUID,
        serviceE164: E164,
        transaction: SDSAnyWriteTransaction
    ) throws -> E164 {
        guard
            let localAci = tsAccountManager.localUuid,
            let localE164 = E164(tsAccountManager.localNumber)
        else {
            throw OWSAssertionError("Missing or invalid local parameters!")
        }

        let localPni = tsAccountManager.localPni

        guard serviceAci == localAci else {
            throw OWSAssertionError("Service ACI \(serviceAci) unexpectedly did not match local ACI!")
        }

        Logger.info(
            """
            localAci: \(localAci),
            localPni: \(localPni?.uuidString ?? "nil"),
            localE164: \(localE164),
            serviceAci: \(serviceAci),
            servicePni: \(servicePni),
            serviceE164: \(serviceE164)")
            """
        )

        SignalRecipient.mergeHighTrust(
            serviceId: ServiceId(serviceAci),
            phoneNumber: serviceE164,
            transaction: transaction
        )
        .markAsRegistered(transaction: transaction)

        if
            serviceE164 != localE164
                || servicePni != localPni
        {
            Logger.info(
                "Recording new phone number: \(serviceE164), PNI: \(servicePni)"
            )

            self.tsAccountManager.updateLocalPhoneNumber(
               E164ObjC(serviceE164),
                aci: serviceAci, // Verified equal to `localAci` above
                pni: servicePni,
                transaction: transaction
            )

            self.storageServiceManager.recordPendingLocalAccountUpdates()

            return serviceE164
        } else {
            return localE164
        }
    }

    // MARK: - Supports change-number

    public func localUserSupportsChangePhoneNumber(transaction: SDSAnyReadTransaction) -> Bool {
        keyValueStore.getBool(
            Constants.localUserSupportsChangePhoneNumberKey,
            defaultValue: false,
            transaction: transaction
        )
    }

    public func setLocalUserSupportsChangePhoneNumber(_ value: Bool, transaction: SDSAnyWriteTransaction) {
        keyValueStore.setBool(
            value,
            key: Constants.localUserSupportsChangePhoneNumberKey,
            transaction: transaction
        )
    }
}
