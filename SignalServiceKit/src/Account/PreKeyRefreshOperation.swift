//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

// We generate 100 one-time prekeys at a time.  We should replenish
// whenever ~2/3 of them have been consumed.
let kEphemeralPreKeysMinimumCount: UInt = 35

@objc(SSKCreatePreKeysOperation)
public class CreatePreKeysOperation: OWSOperation {
    private var accountManager: AccountManager {
        return AccountManager.shared
    }
    private var primaryStorage: OWSPrimaryStorage {
        return OWSPrimaryStorage.shared()
    }

    private var identityKeyManager: OWSIdentityManager {
        return OWSIdentityManager.shared()
    }

    public override func run() {
        Logger.debug("")

        if self.identityKeyManager.identityKeyPair() == nil {
            self.identityKeyManager.generateNewIdentityKey()
        }
        let identityKey: Data = self.identityKeyManager.identityKeyPair()!.publicKey
        let signedPreKeyRecord: SignedPreKeyRecord = self.primaryStorage.generateRandomSignedRecord()
        let preKeyRecords: [PreKeyRecord] = self.primaryStorage.generatePreKeyRecords()

        firstly {
            self.primaryStorage.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
            self.primaryStorage.storePreKeyRecords(preKeyRecords)

            return self.accountManager.setPreKeys(identityKey: identityKey, signedPreKeyRecord: signedPreKeyRecord, preKeyRecords: preKeyRecords)
        }.then { () -> Void in
            signedPreKeyRecord.markAsAcceptedByService()
            self.primaryStorage.setCurrentSignedPrekeyId(signedPreKeyRecord.id)
        }.then { () -> Void in
            Logger.debug("done")
            self.reportSuccess()
        }.catch { error in
            self.reportError(error)
        }.retainUntilComplete()
    }
}

@objc(SSKRotateSignedPreKeyOperation)
public class RotateSignedPreKeyOperation: OWSOperation {
    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private var accountManager: AccountManager {
        return AccountManager.shared
    }

    private var primaryStorage: OWSPrimaryStorage {
        return OWSPrimaryStorage.shared()
    }

    public override func run() {
        Logger.debug("")

        guard tsAccountManager.isRegistered() else {
            Logger.debug("skipping - not registered")
            return
        }

        let signedPreKeyRecord: SignedPreKeyRecord = self.primaryStorage.generateRandomSignedRecord()

        firstly {
            self.primaryStorage.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
            return self.accountManager.setSignedPreKey(signedPreKeyRecord)
        }.then(on: DispatchQueue.global()) { () -> Void in
            Logger.info("Successfully uploaded signed PreKey")
            signedPreKeyRecord.markAsAcceptedByService()
            self.primaryStorage.setCurrentSignedPrekeyId(signedPreKeyRecord.id)

            TSPreKeyManager.clearPreKeyUpdateFailureCount()
            TSPreKeyManager.clearSignedPreKeyRecords()
        }.then { () -> Void in
            Logger.debug("done")
            self.reportSuccess()
        }.catch { error in
            self.reportError(error)
        }.retainUntilComplete()
    }

    override public func didFail(error: Error) {
        switch error {
        case let networkManagerError as NetworkManagerError:
            guard !networkManagerError.isNetworkError else {
                Logger.debug("don't report SPK rotation failure w/ network error")
                return
            }

            guard networkManagerError.statusCode >= 400 && networkManagerError.statusCode <= 599 else {
                Logger.debug("don't report SPK rotation failure w/ non application error")
                return
            }

            TSPreKeyManager.incrementPreKeyUpdateFailureCount()
        default:
            Logger.debug("don't report SPK rotation failure w/ non NetworkManager error: \(error)")
        }
    }
}

@objc(SSKRefreshPreKeysOperation)
public class RefreshPreKeysOperation: OWSOperation {

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private var accountManager: AccountManager {
        return AccountManager.shared
    }

    private var primaryStorage: OWSPrimaryStorage {
        return OWSPrimaryStorage.shared()
    }

    private var identityKeyManager: OWSIdentityManager {
        return OWSIdentityManager.shared()
    }

    public override func run() {
        Logger.debug("")

        guard tsAccountManager.isRegistered() else {
            Logger.debug("skipping - not registered")
            return
        }

        firstly {
            self.accountManager.getPreKeysCount()
        }.then(on: DispatchQueue.global()) { preKeysCount -> Promise<Void> in
            Logger.debug("preKeysCount: \(preKeysCount)")
            guard preKeysCount < kEphemeralPreKeysMinimumCount || self.primaryStorage.currentSignedPrekeyId() == nil else {
                Logger.debug("Available keys sufficient: \(preKeysCount)")
                return Promise(value: ())
            }

            let identityKey: Data = self.identityKeyManager.identityKeyPair()!.publicKey
            let signedPreKeyRecord: SignedPreKeyRecord = self.primaryStorage.generateRandomSignedRecord()
            let preKeyRecords: [PreKeyRecord] = self.primaryStorage.generatePreKeyRecords()

            self.primaryStorage.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
            self.primaryStorage.storePreKeyRecords(preKeyRecords)

            return self.accountManager.setPreKeys(identityKey: identityKey, signedPreKeyRecord: signedPreKeyRecord, preKeyRecords: preKeyRecords).then { () -> Void in
                signedPreKeyRecord.markAsAcceptedByService()
                self.primaryStorage.setCurrentSignedPrekeyId(signedPreKeyRecord.id)

                TSPreKeyManager.clearPreKeyUpdateFailureCount()
                TSPreKeyManager.clearSignedPreKeyRecords()
            }
        }.then { () -> Void in
            Logger.debug("done")
            self.reportSuccess()
        }.catch { error in
            self.reportError(error)
        }.retainUntilComplete()
    }

    public override func didSucceed() {
        TSPreKeyManager.refreshPreKeysDidSucceed()
    }

    override public func didFail(error: Error) {
        switch error {
        case let networkManagerError as NetworkManagerError:
            guard !networkManagerError.isNetworkError else {
                Logger.debug("don't report SPK rotation failure w/ network error")
                return
            }

            guard networkManagerError.statusCode >= 400 && networkManagerError.statusCode <= 599 else {
                Logger.debug("don't report SPK rotation failure w/ non application error")
                return
            }

            TSPreKeyManager.incrementPreKeyUpdateFailureCount()
        default:
            Logger.debug("don't report SPK rotation failure w/ non NetworkManager error: \(error)")
        }
    }
}
