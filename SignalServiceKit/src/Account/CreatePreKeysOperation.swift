//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(SSKCreatePreKeysOperation)
public class CreatePreKeysOperation: OWSOperation {
    private let identity: OWSIdentity

    @objc(initForIdentity:)
    public init(for identity: OWSIdentity) {
        self.identity = identity
    }

    public override func run() {
        Logger.debug("")

        let identityKeyPair: ECKeyPair
        let isNewIdentityKey: Bool
        if let existingIdentityKeyPair = identityManager.identityKeyPair(for: identity) {
            identityKeyPair = existingIdentityKeyPair
            isNewIdentityKey = false
        } else if tsAccountManager.isPrimaryDevice {
            identityKeyPair = identityManager.generateNewIdentityKey(for: identity)
            isNewIdentityKey = true
        } else {
            Logger.warn("cannot create \(identity) pre-keys; missing identity key")
            owsAssertDebug(identity != .aci)
            self.reportCancelled()
            return
        }

        let signalProtocolStore = self.signalProtocolStore(for: identity)
        let signedPreKeyRecord: SignedPreKeyRecord = signalProtocolStore.signedPreKeyStore.generateRandomSignedRecord()
        let preKeyRecords: [PreKeyRecord] = signalProtocolStore.preKeyStore.generatePreKeyRecords()
        let identityKey: Data = identityKeyPair.publicKey

        self.databaseStorage.write { transaction in
            signalProtocolStore.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id,
                                                                    signedPreKeyRecord: signedPreKeyRecord,
                                                                    transaction: transaction)
            signalProtocolStore.preKeyStore.storePreKeyRecords(preKeyRecords, transaction: transaction)
        }

        firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
            guard self.tsAccountManager.isRegisteredAndReady else {
                return Promise.value(())
            }
            return self.messageProcessor.fetchingAndProcessingCompletePromise()
        }.then(on: DispatchQueue.global()) { () -> Promise<Void> in
            self.accountServiceClient.setPreKeys(for: self.identity,
                                                 identityKey: identityKey,
                                                 signedPreKeyRecord: signedPreKeyRecord,
                                                 preKeyRecords: preKeyRecords)
        }.done {
            signedPreKeyRecord.markAsAcceptedByService()
            self.databaseStorage.write { transaction in
                signalProtocolStore.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id,
                                                                        signedPreKeyRecord: signedPreKeyRecord,
                                                                        transaction: transaction)
                signalProtocolStore.signedPreKeyStore.setCurrentSignedPrekeyId(signedPreKeyRecord.id,
                                                                               transaction: transaction)
            }

            Logger.debug("done")
            self.reportSuccess()
        }.catch { error in
            if isNewIdentityKey && self.identity != .aci {
                // Clear out the identity key we just generated if it failed to upload.
                // (Except if it's the ACI identity key, because we're not allowed to clear that without a full reset.)
                self.databaseStorage.write { transaction in
                    self.identityManager.storeIdentityKeyPair(nil, for: self.identity, transaction: transaction)
                }
            }
            self.reportError(withUndefinedRetry: error)
        }
    }
}
