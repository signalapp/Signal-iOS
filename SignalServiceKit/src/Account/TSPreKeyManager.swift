//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public class MessageProcessingOperation: OWSOperation {

    public override func run() {
        Logger.debug("")

        firstly(on: DispatchQueue.global()) {
            self.messageProcessor.fetchingAndProcessingCompletePromise()
        }.done { _ in
            Logger.verbose("Complete.")
            self.reportSuccess()
        }.catch { error in
            owsFailDebug("Error: \(error)")
            self.reportError(SSKUnretryableError.messageProcessingFailed)
        }
    }
}

extension TSPreKeyManager {
    /// Refresh one-time pre-keys for the given identity, and optionally refresh
    /// the signed pre-key.
    static func refreshOneTimePreKeys(
        forIdentity identity: OWSIdentity,
        alsoRefreshSignedPreKey shouldRefreshSignedPreKey: Bool
    ) {
        let refreshOperation = RefreshPreKeysOperation(
            for: identity,
            shouldRefreshSignedPreKey: shouldRefreshSignedPreKey
        )

        operationQueue.addOperation(refreshOperation)
    }

    @objc
    public static func preKeyFailureCount(identity: OWSIdentity, transaction: SDSAnyReadTransaction) -> Int {
        let store = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: identity).signedPreKeyStore
        return Int(store.getPreKeyUpdateFailureCount(tx: transaction.asV2Read))
    }

    @objc
    public static func firstPreKeyFailureDate(identity: OWSIdentity, transaction: SDSAnyReadTransaction) -> Date? {
        let store = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: identity).signedPreKeyStore
        return store.getFirstPreKeyUpdateFailureDate(tx: transaction.asV2Read)
    }
}
