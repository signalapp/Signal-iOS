//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

private let kSignedPreKeyRotationTime: TimeInterval = 2 * kDayInterval

@objc(SSKRotateSignedPreKeyOperation)
public class RotateSignedPreKeyOperation: OWSOperation {
    private let identity: OWSIdentity
    private let shouldSkipIfRecent: Bool

    @objc(initForIdentity:shouldSkipIfRecent:)
    public init(for identity: OWSIdentity, shouldSkipIfRecent: Bool) {
        self.identity = identity
        self.shouldSkipIfRecent = shouldSkipIfRecent
    }

    public override func run() {
        Logger.debug("")

        guard tsAccountManager.isRegistered else {
            Logger.debug("skipping - not registered")
            self.reportCancelled()
            return
        }

        guard identityManager.identityKeyPair(for: identity) != nil else {
            Logger.debug("skipping - no \(identity) identity key")
            self.reportCancelled()
            return
        }

        let signalProtocolStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: identity)
        let currentSignedPreKey = self.databaseStorage.read { transaction in
            signalProtocolStore.signedPreKeyStore.currentSignedPreKey(tx: transaction.asV2Read)
        }

        if shouldSkipIfRecent,
           let currentSignedPreKey,
           abs(currentSignedPreKey.generatedAt.timeIntervalSinceNow) < kSignedPreKeyRotationTime {
            self.reportCancelled()
            return
        }

        let signedPreKeyRecord: SignedPreKeyRecord = signalProtocolStore.signedPreKeyStore.generateRandomSignedRecord()

        firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
            self.messageProcessor.fetchingAndProcessingCompletePromise()
        }.then(on: DispatchQueue.global()) { () -> Promise<Void> in
            self.databaseStorage.write { transaction in
                signalProtocolStore.signedPreKeyStore.storeSignedPreKey(
                    signedPreKeyRecord.id,
                    signedPreKeyRecord: signedPreKeyRecord,
                    tx: transaction.asV2Write
                )
            }
            return self.accountServiceClient.setSignedPreKey(signedPreKeyRecord, for: self.identity)
        }.done(on: DispatchQueue.global()) { () in
            Logger.info("Successfully uploaded \(self.identity) signed PreKey")
            self.databaseStorage.write { transaction in
                signalProtocolStore.signedPreKeyStore.storeSignedPreKeyAsAcceptedAndCurrent(
                    signedPreKeyId: signedPreKeyRecord.id,
                    signedPreKeyRecord: signedPreKeyRecord,
                    tx: transaction.asV2Write
                )

                signalProtocolStore.signedPreKeyStore.cullSignedPreKeyRecords(tx: transaction.asV2Write)
                signalProtocolStore.signedPreKeyStore.clearPreKeyUpdateFailureCount(tx: transaction.asV2Write)
            }

            Logger.info("done")
            self.reportSuccess()
        }.catch(on: DispatchQueue.global()) { error in
            self.reportError(withUndefinedRetry: error)
        }
    }

    override public func didFail(error: Error) {
        guard !error.isNetworkFailureOrTimeout else {
            Logger.debug("don't report SPK rotation failure w/ network error")
            return
        }
        guard let statusCode = error.httpStatusCode else {
            Logger.debug("don't report SPK rotation failure w/ non NetworkManager error: \(error)")
            return
        }
        guard statusCode >= 400 && statusCode <= 599 else {
            Logger.debug("don't report SPK rotation failure w/ non application error")
            return
        }

        let signalProtocolStore = DependenciesBridge.shared.signalProtocolStoreManager.signalProtocolStore(for: identity)
        self.databaseStorage.write { transaction in
            signalProtocolStore.signedPreKeyStore.incrementPreKeyUpdateFailureCount(tx: transaction.asV2Write)
        }
    }
}
