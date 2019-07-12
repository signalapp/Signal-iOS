//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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
public enum OWSUDCertificateExpirationPolicy: Int {
    // We want to try to rotate the sender certificate
    // on a frequent basis, but we don't want to block
    // sending on this.
    case strict
    case permissive
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

@objc
public class OWSUDAccess: NSObject {
    @objc
    public let udAccessKey: SMKUDAccessKey

    @objc
    public let udAccessMode: UnidentifiedAccessMode

    @objc
    public let isRandomKey: Bool

    @objc
    public required init(udAccessKey: SMKUDAccessKey,
                         udAccessMode: UnidentifiedAccessMode,
                         isRandomKey: Bool) {
        self.udAccessKey = udAccessKey
        self.udAccessMode = udAccessMode
        self.isRandomKey = isRandomKey
    }
}

@objc public protocol OWSUDManager: class {

    @objc func setup()

    @objc func trustRoot() -> ECPublicKey

    @objc func isUDVerboseLoggingEnabled() -> Bool

    // MARK: - Recipient State

    @objc
    func setUnidentifiedAccessMode(_ mode: UnidentifiedAccessMode, recipientId: String)

    @objc
    func unidentifiedAccessMode(forRecipientId recipientId: RecipientIdentifier) -> UnidentifiedAccessMode

    @objc
    func udAccessKey(forRecipientId recipientId: RecipientIdentifier) -> SMKUDAccessKey?

    @objc
    func udAccess(forRecipientId recipientId: RecipientIdentifier,
                  requireSyncAccess: Bool) -> OWSUDAccess?

    // MARK: Sender Certificate

    // We use completion handlers instead of a promise so that message sending
    // logic can access the strongly typed certificate data.
    @objc
    func ensureSenderCertificate(success:@escaping (SMKSenderCertificate) -> Void,
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
    private let kUDCurrentSenderCertificateDateKey_Production = "kUDCurrentSenderCertificateDateKey_Production"
    private let kUDCurrentSenderCertificateDateKey_Staging = "kUDCurrentSenderCertificateDateKey_Staging"
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
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            guard self.tsAccountManager.isRegistered else {
                return
            }

            // Any error is silently ignored on startup.
            self.ensureSenderCertificate(certificateExpirationPolicy: .strict).retainUntilComplete()
        }
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(registrationStateDidChange),
                                               name: .RegistrationStateDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: NSNotification.Name.OWSApplicationDidBecomeActive,
                                               object: nil)
    }

    @objc
    func registrationStateDidChange() {
        AssertIsOnMainThread()

        guard tsAccountManager.isRegisteredAndReady else {
            return
        }

        // Any error is silently ignored
        ensureSenderCertificate(certificateExpirationPolicy: .strict).retainUntilComplete()
    }

    @objc func didBecomeActive() {
        AssertIsOnMainThread()

        AppReadiness.runNowOrWhenAppDidBecomeReady {
            guard self.tsAccountManager.isRegistered else {
                return
            }

            // Any error is silently ignored on startup.
            self.ensureSenderCertificate(certificateExpirationPolicy: .strict).retainUntilComplete()
        }
    }

    // MARK: -

    @objc
    public func isUDVerboseLoggingEnabled() -> Bool {
        return false
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
                                        isLocalNumber: Bool,
                                        transaction: YapDatabaseReadTransaction) -> UnidentifiedAccessMode {
        let defaultValue: UnidentifiedAccessMode =  isLocalNumber ? .enabled : .unknown
        guard let existingRawValue = transaction.object(forKey: recipientId, inCollection: kUnidentifiedAccessCollection) as? Int else {
            return defaultValue
        }
        guard let existingValue = UnidentifiedAccessMode(rawValue: existingRawValue) else {
            owsFailDebug("Couldn't parse mode value.")
            return defaultValue
        }
        return existingValue
    }

    @objc
    public func unidentifiedAccessMode(forRecipientId recipientId: RecipientIdentifier) -> UnidentifiedAccessMode {
        var isLocalNumber = false
        if let localNumber = tsAccountManager.localNumber() {
            isLocalNumber = recipientId == localNumber
        }

        var mode: UnidentifiedAccessMode = .unknown
        dbConnection.read { (transaction) in
            mode = self.unidentifiedAccessMode(forRecipientId: recipientId, isLocalNumber: isLocalNumber, transaction: transaction)
        }
        return mode
    }

    @objc
    public func setUnidentifiedAccessMode(_ mode: UnidentifiedAccessMode, recipientId: String) {
        var isLocalNumber = false
        if let localNumber = tsAccountManager.localNumber() {
            if recipientId == localNumber {
                Logger.info("Setting local UD access mode: \(string(forUnidentifiedAccessMode: mode))")
                isLocalNumber = true
            }
        }

        dbConnection.readWrite { (transaction) in
            let oldMode = self.unidentifiedAccessMode(forRecipientId: recipientId, isLocalNumber: isLocalNumber, transaction: transaction)

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
    public func udAccess(forRecipientId recipientId: RecipientIdentifier,
                         requireSyncAccess: Bool) -> OWSUDAccess? {
        if requireSyncAccess {
            guard let localNumber = tsAccountManager.localNumber() else {
                if isUDVerboseLoggingEnabled() {
                    Logger.info("UD disabled for \(recipientId), no local number.")
                }
                owsFailDebug("Missing local number.")
                return nil
            }
            if localNumber != recipientId {
                let selfAccessMode = unidentifiedAccessMode(forRecipientId: localNumber)
                guard selfAccessMode != .disabled else {
                    if isUDVerboseLoggingEnabled() {
                        Logger.info("UD disabled for \(recipientId), UD disabled for sync messages.")
                    }
                    return nil
                }
            }
        }

        let accessMode = unidentifiedAccessMode(forRecipientId: recipientId)
        switch accessMode {
        case .unrestricted:
            // Unrestricted users should use a random key.
            if isUDVerboseLoggingEnabled() {
                Logger.info("UD enabled for \(recipientId) with random key.")
            }
            let udAccessKey = randomUDAccessKey()
            return OWSUDAccess(udAccessKey: udAccessKey, udAccessMode: accessMode, isRandomKey: true)
        case .unknown:
            // Unknown users should use a derived key if possible,
            // and otherwise use a random key.
            if let udAccessKey = udAccessKey(forRecipientId: recipientId) {
                if isUDVerboseLoggingEnabled() {
                    Logger.info("UD unknown for \(recipientId); trying derived key.")
                }
                return OWSUDAccess(udAccessKey: udAccessKey, udAccessMode: accessMode, isRandomKey: false)
            } else {
                if isUDVerboseLoggingEnabled() {
                    Logger.info("UD unknown for \(recipientId); trying random key.")
                }
                let udAccessKey = randomUDAccessKey()
                return OWSUDAccess(udAccessKey: udAccessKey, udAccessMode: accessMode, isRandomKey: true)
            }
        case .enabled:
            guard let udAccessKey = udAccessKey(forRecipientId: recipientId) else {
                if isUDVerboseLoggingEnabled() {
                    Logger.info("UD disabled for \(recipientId), no profile key for this recipient.")
                }
                if (!CurrentAppContext().isRunningTests) {
                    owsFailDebug("Couldn't find profile key for UD-enabled user.")
                }
                return nil
            }
            if isUDVerboseLoggingEnabled() {
                Logger.info("UD enabled for \(recipientId).")
            }
            return OWSUDAccess(udAccessKey: udAccessKey, udAccessMode: accessMode, isRandomKey: false)
        case .disabled:
            if isUDVerboseLoggingEnabled() {
                Logger.info("UD disabled for \(recipientId), UD not enabled for this recipient.")
            }
            return nil
        }
    }

    // MARK: - Sender Certificate

    #if DEBUG
    @objc
    public func hasSenderCertificate() -> Bool {
        return senderCertificate(certificateExpirationPolicy: .permissive) != nil
    }
    #endif

    private func senderCertificate(certificateExpirationPolicy: OWSUDCertificateExpirationPolicy) -> SMKSenderCertificate? {
        if certificateExpirationPolicy == .strict {
            guard let certificateDate = dbConnection.object(forKey: senderCertificateDateKey(), inCollection: kUDCollection) as? Date else {
                return nil
            }
            guard certificateDate.timeIntervalSinceNow < kDayInterval else {
                // Discard certificates that we obtained more than 24 hours ago.
                return nil
            }
        }

        guard let certificateData = dbConnection.object(forKey: senderCertificateKey(), inCollection: kUDCollection) as? Data else {
            return nil
        }

        do {
            let certificate = try SMKSenderCertificate(serializedData: certificateData)

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
        dbConnection.setObject(Date(), forKey: senderCertificateDateKey(), inCollection: kUDCollection)
        dbConnection.setObject(certificateData, forKey: senderCertificateKey(), inCollection: kUDCollection)
    }

    private func senderCertificateKey() -> String {
        return IsUsingProductionService() ? kUDCurrentSenderCertificateKey_Production : kUDCurrentSenderCertificateKey_Staging
    }

    private func senderCertificateDateKey() -> String {
        return IsUsingProductionService() ? kUDCurrentSenderCertificateDateKey_Production : kUDCurrentSenderCertificateDateKey_Staging
    }

    @objc
    public func ensureSenderCertificate(success:@escaping (SMKSenderCertificate) -> Void,
                                        failure:@escaping (Error) -> Void) {
        return ensureSenderCertificate(certificateExpirationPolicy: .permissive,
                                        success: success,
                                        failure: failure)
    }

    private func ensureSenderCertificate(certificateExpirationPolicy: OWSUDCertificateExpirationPolicy,
                                        success:@escaping (SMKSenderCertificate) -> Void,
                                        failure:@escaping (Error) -> Void) {
        firstly {
            ensureSenderCertificate(certificateExpirationPolicy: certificateExpirationPolicy)
        }.map { certificate in
            success(certificate)
        }.catch { error in
            failure(error)
        }.retainUntilComplete()
    }

    public func ensureSenderCertificate(certificateExpirationPolicy: OWSUDCertificateExpirationPolicy) -> Promise<SMKSenderCertificate> {
        // If there is a valid cached sender certificate, use that.
        if let certificate = senderCertificate(certificateExpirationPolicy: certificateExpirationPolicy) {
            return Promise.value(certificate)
        }

        return firstly {
            requestSenderCertificate()
        }.map { (certificate: SMKSenderCertificate) in
            self.setSenderCertificate(certificate.serializedData)
            return certificate
        }
    }

    private func requestSenderCertificate() -> Promise<SMKSenderCertificate> {
        return firstly {
            SignalServiceRestClient().requestUDSenderCertificate()
        }.map { certificateData -> SMKSenderCertificate in
            let certificate = try SMKSenderCertificate(serializedData: certificateData)

            guard self.isValidCertificate(certificate) else {
                throw OWSUDError.invalidData(description: "Invalid sender certificate returned by server")
            }

            return certificate
        }
    }

    private func isValidCertificate(_ certificate: SMKSenderCertificate) -> Bool {
        // Ensure that the certificate will not expire in the next hour.
        // We want a threshold long enough to ensure that any outgoing message
        // sends will complete before the expiration.
        let nowMs = NSDate.ows_millisecondTimeStamp()
        let anHourFromNowMs = nowMs + kHourInMs

        do {
            try certificateValidator.throwswrapped_validate(senderCertificate: certificate, validationTime: anHourFromNowMs)
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
        tsAccountManager.updateAccountAttributes().retainUntilComplete()
    }
}
