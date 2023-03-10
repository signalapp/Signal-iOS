//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

@objc
public class ChangePhoneNumber: NSObject {

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

    public func buildNewChangeToken(
        forNewE164 newE164: E164,
        transaction synchronousTransaction: SDSAnyWriteTransaction
    ) -> Promise<(ChangePhoneNumberPni.Parameters, ChangeToken)> {
        typealias Parameters = ChangePhoneNumberPni.Parameters
        typealias PendingState = ChangePhoneNumberPni.PendingState

        owsAssertDebug(CurrentAppContext().isMainApp)

        guard let localAddress = tsAccountManager.localAddress else {
            return .init(error: OWSAssertionError("Missing local address before change number!"))
        }

        return firstly { () -> Promise<(Parameters, PendingState)> in
            func makeGeneratePniIdentityPromise(
                usingTransaction transaction: SDSAnyWriteTransaction
            ) -> Promise<(Parameters, PendingState)> {
                let localDeviceId = tsAccountManager.storedDeviceId(
                    with: transaction
                )

                return changePhoneNumberPniManager.generatePniIdentity(
                    forNewE164: newE164,
                    localAddress: localAddress,
                    localDeviceId: localDeviceId,
                    transaction: transaction.asV2Write
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
                        changeToken: incompleteChangeToken,
                        localAddress: localAddress
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
                if FeatureFlags.useChangePhoneNumberPniParameters {
                    return ChangeToken(pniPendingState: pendingState)
                }

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

    public func changeDidComplete(
        changeToken: ChangeToken,
        successfully changeWasSuccesful: Bool,
        transaction: SDSAnyWriteTransaction
    ) {
        owsAssertDebug(CurrentAppContext().isMainApp)

        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing local address!")
            return
        }

        if
            changeWasSuccesful,
            let pniPendingState = changeToken.pniPendingState
        {
            changePhoneNumberPniManager.finalizePniIdentity(
                withPendingState: pniPendingState,
                localAddress: localAddress,
                transaction: transaction.asV2Write
            )
        }

        incompleteChangeTokenStore.clear(
            changeToken: changeToken,
            transaction: transaction
        )
    }

    /// Take steps to recover from an interrupted change-number operation,
    /// indicated by the presence of the given change token.
    private func recoverIncompleteChangeToken(
        changeToken: ChangeToken,
        localAddress: SignalServiceAddress
    ) -> Promise<Void> {
        firstly { () -> Promise<WhoAmIRequestFactory.Responses.WhoAmI> in
            self.accountServiceClient.getAccountWhoAmI()
        }.done(on: DispatchQueue.global()) { whoAmIResponse in
            try self.databaseStorage.write { transaction in
                let changeWasSuccessful: Bool

                if let pniPendingState = changeToken.pniPendingState {
                    if pniPendingState.newE164.stringValue == whoAmIResponse.e164 {
                        changeWasSuccessful = true
                    } else {
                        changeWasSuccessful = false
                    }
                } else {
                    // Legacy change-number attempt - take whatever is on the
                    // service and ensure we have the same state locally, then
                    // clear the token.
                    changeWasSuccessful = true
                }

                _ = try self.updateLocalPhoneNumber(
                    forServiceAci: whoAmIResponse.aci,
                    servicePni: whoAmIResponse.pni,
                    serviceE164: whoAmIResponse.e164,
                    transaction: transaction
                )

                self.changeDidComplete(
                    changeToken: changeToken,
                    successfully: changeWasSuccessful,
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
                    successfully: false,
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

        guard !appExpiry.isExpired else {
            owsFailDebug("appExpiry.")
            return
        }

        guard
            CurrentAppContext().isMainApp,
            tsAccountManager.isRegisteredAndReady
        else {
            return
        }

        guard let localAddress = tsAccountManager.localAddress else {
            owsFailDebug("Missing local address!")
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

        recoverIncompleteChangeToken(
            changeToken: incompleteChangeToken,
            localAddress: localAddress
        ).done(on: DispatchQueue.global()) {
            Logger.info("Recovered incomplete change token!")
        }.catch(on: DispatchQueue.global()) { error in
            Logger.info("Failed to recover incomplete change token: \(error)")
        }
    }

    // MARK: - Update the local phone number

    @objc
    public func updateLocalPhoneNumber() {
        // TODO: [CNPNI] This is no longer a safe thing to do

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
    public func updateLocalPhoneNumber(
        forServiceAci serviceAci: UUID,
        servicePni: UUID,
        serviceE164: String?,
        transaction: SDSAnyWriteTransaction
    ) throws -> E164 {
        guard let serviceE164 = E164(serviceE164) else {
            throw OWSAssertionError("Missing or invalid service e164.")
        }

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

        let addressFromServiceParams = SignalServiceAddress(
            uuid: serviceAci,
            e164: serviceE164
        )

        SignalRecipient.fetchOrCreate(
            for: addressFromServiceParams,
            trustLevel: .high,
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
                serviceE164.stringValue,
                aci: serviceAci, // Verified equal to `localAci` above
                pni: servicePni,
                shouldUpdateStorageService: true,
                transaction: transaction
            )

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
