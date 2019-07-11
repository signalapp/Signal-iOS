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
    func setUnidentifiedAccessMode(_ mode: UnidentifiedAccessMode, address: SignalServiceAddress)

    @objc
    func unidentifiedAccessMode(forAddress address: SignalServiceAddress) -> UnidentifiedAccessMode

    @objc
    func udAccessKey(forAddress address: SignalServiceAddress) -> SMKUDAccessKey?

    @objc
    func udAccess(forAddress address: SignalServiceAddress,
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
    private let kUnidentifiedAccessPhoneNumberCollection = "kUnidentifiedAccessCollection"
    private let kUnidentifiedAccessUUIDCollection = "kUnidentifiedAccessUUIDCollection"

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

    private func unidentifiedAccessMode(forAddress address: SignalServiceAddress,
                                        transaction: YapDatabaseReadWriteTransaction) -> UnidentifiedAccessMode {
        let defaultValue: UnidentifiedAccessMode =  address.isLocalAddress ? .enabled : .unknown

        let existingUUIDValue: UnidentifiedAccessMode?
        if let uuidString = address.uuidString,
            let existingRawValue = transaction.object(forKey: uuidString, inCollection: kUnidentifiedAccessUUIDCollection) as? Int {

            guard let value = UnidentifiedAccessMode(rawValue: existingRawValue) else {
                owsFailDebug("Couldn't parse mode value.")
                return defaultValue
            }
            existingUUIDValue = value
        } else {
            existingUUIDValue = nil
        }

        let existingPhoneNumberValue: UnidentifiedAccessMode?
        if let phoneNumber = address.phoneNumber,
            let existingRawValue = transaction.object(forKey: phoneNumber, inCollection: kUnidentifiedAccessPhoneNumberCollection) as? Int {

            guard let value = UnidentifiedAccessMode(rawValue: existingRawValue) else {
                owsFailDebug("Couldn't parse mode value.")
                return defaultValue
            }
            existingPhoneNumberValue = value
        } else {
            existingPhoneNumberValue = nil
        }

        let existingValue: UnidentifiedAccessMode?

        if let existingUUIDValue = existingUUIDValue, let existingPhoneNumberValue = existingPhoneNumberValue {

            // If UUID and Phone Number setting don't align, defer to UUID and update phone number
            if existingPhoneNumberValue != existingUUIDValue {
                owsFailDebug("UUID and Phone Number unexpectedly have different UD values")
                Logger.info("Unexpected UD value mismatch, migrating phone number value: \(existingPhoneNumberValue) to uuid value: \(existingUUIDValue)")
                transaction.setObject(existingUUIDValue.rawValue, forKey: address.phoneNumber!, inCollection: kUnidentifiedAccessPhoneNumberCollection)
            }

            existingValue = existingUUIDValue
        } else if let existingPhoneNumberValue = existingPhoneNumberValue {
            existingValue = existingPhoneNumberValue

            // We had phone number entry but not UUID, update UUID value
            if let uuidString = address.uuidString {
                transaction.setObject(existingPhoneNumberValue.rawValue, forKey: uuidString, inCollection: kUnidentifiedAccessUUIDCollection)
            }
        } else if let existingUUIDValue = existingUUIDValue {
            existingValue = existingUUIDValue

            // We had UUID entry but not phone number, update phone number value
            if let phoneNumber = address.phoneNumber {
                transaction.setObject(existingUUIDValue.rawValue, forKey: phoneNumber, inCollection: kUnidentifiedAccessPhoneNumberCollection)
            }
        } else {
            existingValue = nil
        }

        return existingValue ?? defaultValue
    }

    @objc
    public func unidentifiedAccessMode(forAddress address: SignalServiceAddress) -> UnidentifiedAccessMode {
        var mode: UnidentifiedAccessMode = .unknown
        dbConnection.readWrite { (transaction) in
            mode = self.unidentifiedAccessMode(forAddress: address, transaction: transaction)
        }
        return mode
    }

    @objc
    public func setUnidentifiedAccessMode(_ mode: UnidentifiedAccessMode, address: SignalServiceAddress) {
        if address.isLocalAddress {
            Logger.info("Setting local UD access mode: \(string(forUnidentifiedAccessMode: mode))")
        }

        dbConnection.readWrite { (transaction) in
            let oldMode = self.unidentifiedAccessMode(forAddress: address, transaction: transaction)

            if let uuidString = address.uuidString {
                transaction.setObject(mode.rawValue as Int, forKey: uuidString, inCollection: self.kUnidentifiedAccessUUIDCollection)
            }

            if let phoneNumber = address.phoneNumber {
                transaction.setObject(mode.rawValue as Int, forKey: phoneNumber, inCollection: self.kUnidentifiedAccessPhoneNumberCollection)
            }

            if mode != oldMode {
                Logger.info("Setting UD access mode for \(address): \(string(forUnidentifiedAccessMode: oldMode)) ->  \(string(forUnidentifiedAccessMode: mode))")
            }
        }
    }

    // Returns the UD access key for a given recipient
    // if we have a valid profile key for them.
    @objc
    public func udAccessKey(forAddress address: SignalServiceAddress) -> SMKUDAccessKey? {
        guard let profileKey = profileManager.profileKeyData(for: address) else {
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
    public func udAccess(forAddress address: SignalServiceAddress,
                         requireSyncAccess: Bool) -> OWSUDAccess? {
        if requireSyncAccess {
            guard tsAccountManager.localAddress != nil else {
                if isUDVerboseLoggingEnabled() {
                    Logger.info("UD disabled for \(address), no local number.")
                }
                owsFailDebug("Missing local number.")
                return nil
            }
            if address.isLocalAddress {
                let selfAccessMode = unidentifiedAccessMode(forAddress: address)
                guard selfAccessMode != .disabled else {
                    if isUDVerboseLoggingEnabled() {
                        Logger.info("UD disabled for \(address), UD disabled for sync messages.")
                    }
                    return nil
                }
            }
        }

        let accessMode = unidentifiedAccessMode(forAddress: address)
        switch accessMode {
        case .unrestricted:
            // Unrestricted users should use a random key.
            if isUDVerboseLoggingEnabled() {
                Logger.info("UD enabled for \(address) with random key.")
            }
            let udAccessKey = randomUDAccessKey()
            return OWSUDAccess(udAccessKey: udAccessKey, udAccessMode: accessMode, isRandomKey: true)
        case .unknown:
            // Unknown users should use a derived key if possible,
            // and otherwise use a random key.
            if let udAccessKey = udAccessKey(forAddress: address) {
                if isUDVerboseLoggingEnabled() {
                    Logger.info("UD unknown for \(address); trying derived key.")
                }
                return OWSUDAccess(udAccessKey: udAccessKey, udAccessMode: accessMode, isRandomKey: false)
            } else {
                if isUDVerboseLoggingEnabled() {
                    Logger.info("UD unknown for \(address); trying random key.")
                }
                let udAccessKey = randomUDAccessKey()
                return OWSUDAccess(udAccessKey: udAccessKey, udAccessMode: accessMode, isRandomKey: true)
            }
        case .enabled:
            guard let udAccessKey = udAccessKey(forAddress: address) else {
                if isUDVerboseLoggingEnabled() {
                    Logger.info("UD disabled for \(address), no profile key for this recipient.")
                }
                if (!CurrentAppContext().isRunningTests) {
                    owsFailDebug("Couldn't find profile key for UD-enabled user.")
                }
                return nil
            }
            if isUDVerboseLoggingEnabled() {
                Logger.info("UD enabled for \(address).")
            }
            return OWSUDAccess(udAccessKey: udAccessKey, udAccessMode: accessMode, isRandomKey: false)
        case .disabled:
            if isUDVerboseLoggingEnabled() {
                Logger.info("UD disabled for \(address), UD not enabled for this recipient.")
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
        //
        // NOTE: We use a "strict" expiration policy.
        if let certificate = senderCertificate(certificateExpirationPolicy: certificateExpirationPolicy) {
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
