//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
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
        if let existingIdentityKeyPair = identityManager.identityKeyPair(for: identity) {
            identityKeyPair = existingIdentityKeyPair
        } else if tsAccountManager.isPrimaryDevice {
            identityKeyPair = identityManager.generateNewIdentityKey(for: identity)
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

        firstly(on: .global()) { () -> Promise<Void> in
            guard self.tsAccountManager.isRegisteredAndReady else {
                return Promise.value(())
            }
            return self.messageProcessor.fetchingAndProcessingCompletePromise()
        }.then(on: .global()) { () -> Promise<Void> in
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
            self.reportError(withUndefinedRetry: error)
        }
    }
}
