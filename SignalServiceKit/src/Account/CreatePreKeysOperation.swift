//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(SSKCreatePreKeysOperation)
public class CreatePreKeysOperation: OWSOperation {

    // MARK: - Dependencies

    private var accountServiceClient: AccountServiceClient {
        return SSKEnvironment.shared.accountServiceClient
    }

    private var preKeyStore: SSKPreKeyStore {
        return SSKEnvironment.shared.preKeyStore
    }

    private var signedPreKeyStore: SSKSignedPreKeyStore {
        return SSKEnvironment.shared.signedPreKeyStore
    }

    private var identityKeyManager: OWSIdentityManager {
        return OWSIdentityManager.shared()
    }

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private var messageProcessor: MessageProcessor {
        return SSKEnvironment.shared.messageProcessor
    }

    private var tsAccountManager: TSAccountManager {
        return .shared()
    }

    // MARK: -

    public override func run() {
        Logger.debug("")

        if self.identityKeyManager.identityKeyPair() == nil {
            self.identityKeyManager.generateNewIdentityKey()
        }
        let identityKey: Data = self.identityKeyManager.identityKeyPair()!.publicKey
        let signedPreKeyRecord: SignedPreKeyRecord = self.signedPreKeyStore.generateRandomSignedRecord()
        let preKeyRecords: [PreKeyRecord] = self.preKeyStore.generatePreKeyRecords()

        self.databaseStorage.write { transaction in
            self.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id,
                                                     signedPreKeyRecord: signedPreKeyRecord,
                                                     transaction: transaction)
        }
        self.preKeyStore.storePreKeyRecords(preKeyRecords)

        firstly(on: .global()) { () -> Promise<Void> in
            guard self.tsAccountManager.isRegisteredAndReady else {
                return Promise.value(())
            }
            return self.messageProcessor.fetchingAndProcessingCompletePromise()
        }.then(on: .global()) { () -> Promise<Void> in
            self.accountServiceClient.setPreKeys(identityKey: identityKey,
                                                 signedPreKeyRecord: signedPreKeyRecord,
                                                 preKeyRecords: preKeyRecords)
        }.done {
            signedPreKeyRecord.markAsAcceptedByService()
            self.databaseStorage.write { transaction in
                self.signedPreKeyStore.storeSignedPreKey(signedPreKeyRecord.id,
                                                         signedPreKeyRecord: signedPreKeyRecord,
                                                         transaction: transaction)
            }
            self.signedPreKeyStore.setCurrentSignedPrekeyId(signedPreKeyRecord.id)

            Logger.debug("done")
            self.reportSuccess()
        }.catch { error in
            self.reportError(withUndefinedRetry: error)
        }
    }
}
