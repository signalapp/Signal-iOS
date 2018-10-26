//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalMetadataKit
import SignalCoreKit

public enum OWSUDError: Error {
    case assertionError(description: String)
    case invalidData(description: String)
}

@objc
public enum UnidentifiedAccessMode: Int {
    case unknown
    case enabled
    case disabled
    case unrestricted
}

private func string(forUnidentifiedAccessMode mode: UnidentifiedAccessMode) -> String {
    switch mode {
    case .unknown:
        return "unknown"
    case .enabled:
        return "enabled"
    case .disabled:
        return "disabled"
    case .unrestricted:
        return "unrestricted"
    }
}

@objc public protocol OWSUDManager: class {

    @objc func setup()

    @objc func trustRoot() -> ECPublicKey

    @objc func isUDEnabled() -> Bool

    @objc func isUDVerboseLoggingEnabled() -> Bool

    // MARK: - Recipient State

    @objc
    func setUnidentifiedAccessMode(_ mode: UnidentifiedAccessMode, recipientId: String)

    @objc
    func randomUDAccessKey() -> SMKUDAccessKey

    @objc
    func unidentifiedAccessMode(forRecipientId recipientId: RecipientIdentifier) -> UnidentifiedAccessMode

    @objc
    func udAccessKey(forRecipientId recipientId: RecipientIdentifier) -> SMKUDAccessKey?

    @objc
    func udSendAccessKey(forRecipientId recipientId: RecipientIdentifier) -> SMKUDAccessKey?

    // MARK: Sender Certificate

    // We use completion handlers instead of a promise so that message sending
    // logic can access the strongly typed certificate data.
    @objc
    func ensureSenderCertificateObjC(success:@escaping (SMKSenderCertificate) -> Void,
                                            failure:@escaping (Error) -> Void)

    // MARK: Unrestricted Access

    @objc
    func shouldAllowUnrestrictedAccessLocal() -> Bool
    @objc
    func setShouldAllowUnrestrictedAccessLocal(_ value: Bool)
}

// MARK: -

@objc
public class OWSUDManagerImpl: NSObject, OWSUDManager {

    private let dbConnection: YapDatabaseConnection

    // MARK: Local Configuration State
    private let kUDCollection = "kUDCollection"
    private let kUDCurrentSenderCertificateKey_Production = "kUDCurrentSenderCertificateKey_Production"
    private let kUDCurrentSenderCertificateKey_Staging = "kUDCurrentSenderCertificateKey_Staging"
    private let kUDUnrestrictedAccessKey = "kUDUnrestrictedAccessKey"

    // MARK: Recipient State
    private let kUnidentifiedAccessCollection = "kUnidentifiedAccessCollection"

    var certificateValidator: SMKCertificateValidator

    @objc
    public required init(primaryStorage: OWSPrimaryStorage) {
        self.dbConnection = primaryStorage.newDatabaseConnection()
        self.certificateValidator = SMKCertificateDefaultValidator(trustRoot: OWSUDManagerImpl.trustRoot())

        super.init()

        SwiftSingletons.register(self)
    }

    @objc public func setup() {
        AppReadiness.runNowOrWhenAppIsReady {
            guard TSAccountManager.isRegistered() else {
                return
            }
            self.ensureSenderCertificate().retainUntilComplete()
        }
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(registrationStateDidChange),
                                               name: .RegistrationStateDidChange,
                                               object: nil)
    }

    @objc
    func registrationStateDidChange() {
        AssertIsOnMainThread()

        ensureSenderCertificate().retainUntilComplete()
    }

    // MARK: -

    @objc
    public func isUDEnabled() -> Bool {
        // Only enable UD if UD is supported by all linked devices,
        // so that sync messages can also be sent via UD.
        guard let localNumber = tsAccountManager.localNumber() else {
            return false
        }
        let ourAccessMode = unidentifiedAccessMode(forRecipientId: localNumber)
        return ourAccessMode == .enabled || ourAccessMode == .unrestricted
    }

    @objc
    public func isUDVerboseLoggingEnabled() -> Bool {
        return true
    }

    // MARK: - Dependencies

    private var profileManager: ProfileManagerProtocol {
        return SSKEnvironment.shared.profileManager
    }

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    // MARK: - Recipient state

    @objc
    public func randomUDAccessKey() -> SMKUDAccessKey {
        return SMKUDAccessKey(randomKeyData: ())
    }

    private func unidentifiedAccessMode(forRecipientId recipientId: RecipientIdentifier,
                                        transaction: YapDatabaseReadTransaction) -> UnidentifiedAccessMode {
        guard let existingRawValue = transaction.object(forKey: recipientId, inCollection: kUnidentifiedAccessCollection) as? Int else {
            return .unknown
        }
        guard let existingValue = UnidentifiedAccessMode(rawValue: existingRawValue) else {
            return .unknown
        }
        return existingValue
    }

    @objc
    public func unidentifiedAccessMode(forRecipientId recipientId: RecipientIdentifier) -> UnidentifiedAccessMode {
        var mode: UnidentifiedAccessMode = .unknown
        dbConnection.read { (transaction) in
            mode = self.unidentifiedAccessMode(forRecipientId: recipientId, transaction: transaction)
        }
        return mode
    }

    @objc
    public func setUnidentifiedAccessMode(_ mode: UnidentifiedAccessMode, recipientId: String) {
        if let localNumber = tsAccountManager.localNumber() {
            if recipientId == localNumber {
                Logger.info("Setting local UD access mode: \(string(forUnidentifiedAccessMode: mode))")
            }
        }

        dbConnection.readWrite { (transaction) in
            let oldMode = self.unidentifiedAccessMode(forRecipientId: recipientId, transaction: transaction)

            transaction.setObject(mode.rawValue as Int, forKey: recipientId, inCollection: self.kUnidentifiedAccessCollection)

            if mode != oldMode {
                Logger.info("Setting UD access mode for \(recipientId): \(string(forUnidentifiedAccessMode: oldMode)) ->  \(string(forUnidentifiedAccessMode: mode))")
            }
        }
    }

    // Returns the UD access key for a given recipient
    // if we have a valid profile key for them.
    @objc
    public func udAccessKey(forRecipientId recipientId: RecipientIdentifier) -> SMKUDAccessKey? {
        guard let profileKey = profileManager.profileKeyData(forRecipientId: recipientId) else {
            // Mark as "not a UD recipient".
            return nil
        }
        do {
            let udAccessKey = try SMKUDAccessKey(profileKey: profileKey)
            return udAccessKey
        } catch {
            Logger.error("Could not determine udAccessKey: \(error)")
            return nil
        }
    }

    // Returns the UD access key for sending to a given recipient.
    @objc
    public func udSendAccessKey(forRecipientId recipientId: RecipientIdentifier) -> SMKUDAccessKey? {
        // This check is currently redundant with the "send access key for local number"
        // check below, but behavior of isUDEnabled() may change.
        guard isUDEnabled() else {
            if isUDVerboseLoggingEnabled() {
                Logger.info("UD Send disabled for \(recipientId), UD disabled.")
            }
            return nil
        }
        guard let localNumber = tsAccountManager.localNumber() else {
            if isUDVerboseLoggingEnabled() {
                Logger.info("UD Send disabled for \(recipientId), no local number.")
            }
            return nil
        }
        if localNumber != recipientId {
            guard udSendAccessKey(forRecipientId: localNumber) != nil else {
                if isUDVerboseLoggingEnabled() {
                    Logger.info("UD Send disabled for \(recipientId), UD disabled for sync messages.")
                }
                return nil
            }
        }
        let accessMode = unidentifiedAccessMode(forRecipientId: localNumber)
        if accessMode == .unrestricted {
            if isUDVerboseLoggingEnabled() {
                Logger.info("UD Send enabled for \(recipientId) with random key.")
            }
            return randomUDAccessKey()
        }
        guard accessMode == .enabled else {
            if isUDVerboseLoggingEnabled() {
                Logger.info("UD Send disabled for \(recipientId), UD not enabled for this recipient.")
            }
            return nil
        }
        if isUDVerboseLoggingEnabled() {
            Logger.info("UD Send enabled for \(recipientId).")
        }
        return udAccessKey(forRecipientId: recipientId)
    }

    // MARK: - Sender Certificate

    #if DEBUG
    @objc
    public func hasSenderCertificate() -> Bool {
        return senderCertificate() != nil
    }
    #endif

    private func senderCertificate() -> SMKSenderCertificate? {
        guard let certificateData = dbConnection.object(forKey: senderCertificateKey(), inCollection: kUDCollection) as? Data else {
            return nil
        }

        do {
            let certificate = try SMKSenderCertificate.parse(data: certificateData)

            guard isValidCertificate(certificate) else {
                Logger.warn("Current sender certificate is not valid.")
                return nil
            }

            return certificate
        } catch {
            owsFailDebug("Certificate could not be parsed: \(error)")
            return nil
        }
    }

    func setSenderCertificate(_ certificateData: Data) {
        dbConnection.setObject(certificateData, forKey: senderCertificateKey(), inCollection: kUDCollection)
    }

    private func senderCertificateKey() -> String {
        return IsUsingProductionService() ? kUDCurrentSenderCertificateKey_Production : kUDCurrentSenderCertificateKey_Staging
    }

    @objc
    public func ensureSenderCertificateObjC(success:@escaping (SMKSenderCertificate) -> Void,
                                            failure:@escaping (Error) -> Void) {
        firstly {
            ensureSenderCertificate()
        }.map { certificate in
            success(certificate)
        }.catch { error in
            failure(error)
        }.retainUntilComplete()
    }

    public func ensureSenderCertificate() -> Promise<SMKSenderCertificate> {
        // If there is a valid cached sender certificate, use that.
        if let certificate = senderCertificate() {
            return Promise.value(certificate)
        }

        // Try to obtain a new sender certificate.
        return firstly {
            requestSenderCertificate()
        }.map { (certificateData: Data, certificate: SMKSenderCertificate) in

            // Cache the current sender certificate.
            self.setSenderCertificate(certificateData)

            return certificate
        }
    }

    private func requestSenderCertificate() -> Promise<(certificateData: Data, certificate: SMKSenderCertificate)> {
        return firstly {
            SignalServiceRestClient().requestUDSenderCertificate()
        }.map { certificateData -> (certificateData: Data, certificate: SMKSenderCertificate) in
            let certificate = try SMKSenderCertificate.parse(data: certificateData)

            guard self.isValidCertificate(certificate) else {
                throw OWSUDError.invalidData(description: "Invalid sender certificate returned by server")
            }

            return (certificateData: certificateData, certificate: certificate)
        }
    }

    private func isValidCertificate(_ certificate: SMKSenderCertificate) -> Bool {
        // Ensure that the certificate will not expire in the next hour.
        // We want a threshold long enough to ensure that any outgoing message
        // sends will complete before the expiration.
        let nowMs = NSDate.ows_millisecondTimeStamp()
        let anHourFromNowMs = nowMs + kHourInMs

        do {
            try certificateValidator.validate(senderCertificate: certificate, validationTime: anHourFromNowMs)
            return true
        } catch {
            OWSLogger.error("Invalid certificate")
            return false
        }
    }

    @objc
    public func trustRoot() -> ECPublicKey {
        return OWSUDManagerImpl.trustRoot()
    }

    @objc
    public class func trustRoot() -> ECPublicKey {
        guard let trustRootData = NSData(fromBase64String: kUDTrustRoot) else {
            // This exits.
            owsFail("Invalid trust root data.")
        }

        do {
            return try ECPublicKey(serializedKeyData: trustRootData as Data)
        } catch {
            // This exits.
            owsFail("Invalid trust root.")
        }
    }

    // MARK: - Unrestricted Access

    @objc
    public func shouldAllowUnrestrictedAccessLocal() -> Bool {
        return dbConnection.bool(forKey: kUDUnrestrictedAccessKey, inCollection: kUDCollection, defaultValue: false)
    }

    @objc
    public func setShouldAllowUnrestrictedAccessLocal(_ value: Bool) {
        dbConnection.setBool(value, forKey: kUDUnrestrictedAccessKey, inCollection: kUDCollection)

        // Try to update the account attributes to reflect this change.
        tsAccountManager.updateAccountAttributes()
    }
}
