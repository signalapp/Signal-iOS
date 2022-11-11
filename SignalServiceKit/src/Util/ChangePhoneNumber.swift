//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

@objc
public class ChangePhoneNumber: NSObject {

    @objc
    public static var shared: ChangePhoneNumber { SSKEnvironment.shared.changePhoneNumber }

    @objc
    public override init() {
        super.init()

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            Self.verifyLocalPhoneNumberIfNecessary()
        }
    }

    public struct ChangeToken {
        fileprivate let changeId: String
    }

    // incompleteChangeStore persists the set of changes that
    // were begun (by this or previous launches of the app)
    // and not yet marked as complete.
    private static let incompleteChangeStore = SDSKeyValueStore(collection: "ChangePhoneNumber.incompleteChanges")
    private static let lastVerifyAppVersion4Key = "lastVerifyAppVersion4Key"

    public static func changeWillBegin(transaction: SDSAnyWriteTransaction) -> ChangeToken {
        owsAssertDebug(CurrentAppContext().isMainApp)

        // Generate and insert a new "change phone number" id.
        let changeId = UUID().uuidString
        incompleteChangeStore.setString(changeId, key: changeId, transaction: transaction)
        return ChangeToken(changeId: changeId)
    }

    public static func changeDidComplete(changeToken: ChangeToken, transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(CurrentAppContext().isMainApp)

        clear(changeId: changeToken.changeId, transaction: transaction)
    }

    private static func clear(changeId: String, transaction: SDSAnyWriteTransaction) {
        incompleteChangeStore.removeValue(forKey: changeId, transaction: transaction)
    }

    private static func verifyDidComplete(changeIds: Set<String>, transaction: SDSAnyWriteTransaction) {
        Self.keyValueStore.setString(AppVersion.shared().currentAppVersion4,
                                     key: lastVerifyAppVersion4Key,
                                     transaction: transaction)

        for changeId in changeIds {
            clear(changeId: changeId, transaction: transaction)
        }
    }

    private enum VerifyStatus {
        case doNotVerify
        case verify(changeIds: Set<String>)
    }

    private static func buildVerifyStatus(transaction: SDSAnyReadTransaction) -> VerifyStatus {
        // Verify if there are incomplete changes in the db.
        let incompleteChangeIds = Set(incompleteChangeStore.allKeys(transaction: transaction))
        guard incompleteChangeIds.isEmpty else {
            return .verify(changeIds: incompleteChangeIds)
        }
        // Verify if we haven't verified at least once on this app version.
        let currentAppVersion4 = AppVersion.shared().currentAppVersion4
        let lastVerifyAppVersion4: String? = Self.keyValueStore.getString(lastVerifyAppVersion4Key,
                                                                          transaction: transaction)
        guard currentAppVersion4 == lastVerifyAppVersion4 else {
            return .verify(changeIds: Set())
        }
#if DEBUG
        // Always verify in debug builds.
        return .verify(changeIds: Set())
        #else
        return .doNotVerify
#endif
    }

    private static func verifyLocalPhoneNumberIfNecessary() {
        guard AppReadiness.isAppReady else {
            owsFailDebug("isAppReady.")
            return
        }
        guard !appExpiry.isExpired else {
            owsFailDebug("appExpiry.")
            return
        }
        guard CurrentAppContext().isMainApp,
              tsAccountManager.isRegisteredAndReady else {
            return
        }

        let verifyStatus = databaseStorage.read { transaction in
            Self.buildVerifyStatus(transaction: transaction)
        }

        switch verifyStatus {
        case .doNotVerify:
            return
        case .verify(let changeIds):
            firstly {
                Self.updateLocalPhoneNumberPromise()
            }.done(on: .global()) { _ in
                Self.databaseStorage.write { transaction in
                    Self.verifyDidComplete(changeIds: changeIds, transaction: transaction)
                }
            }.catch(on: .global()) { error in
                owsFailDebugUnlessNetworkFailure(error)

                if !error.isNetworkFailureOrTimeout {
                    Self.databaseStorage.write { transaction in
                        Self.verifyDidComplete(changeIds: changeIds, transaction: transaction)
                    }
                }
            }
        }
    }

    @objc
    public static func updateLocalPhoneNumber() {
        firstly {
            Self.updateLocalPhoneNumberPromise()
        }.catch(on: .global()) { error in
            owsFailDebugUnlessNetworkFailure(error)
        }
    }

    public struct LocalPhoneNumber {
        public let localPhoneNumber: String
    }

    public static func updateLocalPhoneNumberPromise() -> Promise<LocalPhoneNumber> {
        firstly { () -> Promise<WhoAmIResponse> in
            Self.accountServiceClient.getAccountWhoAmI()
        }.map(on: .global()) { whoAmIResponse in
            try Self.updateLocalPhoneNumber(from: whoAmIResponse)
        }
    }

    public static func updateLocalPhoneNumber(from whoAmIResponse: WhoAmIResponse) throws -> LocalPhoneNumber {
        guard let localUuid = tsAccountManager.localUuid else {
            throw OWSAssertionError("Missing localUuid.")
        }
        guard let localPhoneNumber = tsAccountManager.localNumber else {
            throw OWSAssertionError("Missing localPhoneNumber.")
        }
        let localPni = tsAccountManager.localPni

        let serviceUuid = whoAmIResponse.aci
        guard let servicePhoneNumber = whoAmIResponse.e164 else {
            throw OWSAssertionError("Missing servicePhoneNumber.")
        }
        guard serviceUuid == localUuid else {
            throw OWSAssertionError("Unexpected uuid: \(serviceUuid) != \(localUuid)")
        }
        let servicePni = whoAmIResponse.pni

        Logger.info("localUuid: \(localUuid), localPhoneNumber: \(localPhoneNumber), serviceUuid: \(serviceUuid), servicePhoneNumber: \(servicePhoneNumber)")

        databaseStorage.write { transaction in
            let address = SignalServiceAddress(uuid: serviceUuid, phoneNumber: servicePhoneNumber)
            SignalRecipient.mark(asRegisteredAndGet: address,
                                 trustLevel: .high,
                                 transaction: transaction)

            if servicePhoneNumber != localPhoneNumber || servicePni != localPni {
                Logger.info("Recording new phone number: \(servicePhoneNumber), pni: \(servicePni)")

                Self.tsAccountManager.updateLocalPhoneNumber(servicePhoneNumber,
                                                             aci: localUuid,
                                                             pni: servicePni,
                                                             shouldUpdateStorageService: true,
                                                             transaction: transaction)
            }
        }

        return LocalPhoneNumber(localPhoneNumber: servicePhoneNumber)
    }

    private static let keyValueStore = SDSKeyValueStore(collection: "ChangePhoneNumber")
    private static let localUserSupportsChangePhoneNumberKey = "localUserSupportsChangePhoneNumber"

    public static func localUserSupportsChangePhoneNumber(transaction: SDSAnyReadTransaction) -> Bool {
        keyValueStore.getBool(localUserSupportsChangePhoneNumberKey, defaultValue: false, transaction: transaction)
    }

    public static func setLocalUserSupportsChangePhoneNumber(_ value: Bool, transaction: SDSAnyWriteTransaction) {
        keyValueStore.setBool(value, key: localUserSupportsChangePhoneNumberKey, transaction: transaction)
    }
}
