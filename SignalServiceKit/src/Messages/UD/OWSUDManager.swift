//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

@objc
public class OWSUDSendingAccess: NSObject {

    @objc
    public let udAccess: OWSUDAccess

    @objc
    public let senderCertificate: SMKSenderCertificate

    init(udAccess: OWSUDAccess, senderCertificate: SMKSenderCertificate) {
        self.udAccess = udAccess
        self.senderCertificate = senderCertificate
    }
}

@objc public protocol OWSUDManager: class {
    @objc
    var keyValueStore: SDSKeyValueStore { get }
    @objc
    var phoneNumberAccessStore: SDSKeyValueStore { get }
    @objc
    var uuidAccessStore: SDSKeyValueStore { get }

    @objc func setup()

    @objc func trustRoot() -> ECPublicKey

    @objc func isUDVerboseLoggingEnabled() -> Bool

    // MARK: - Recipient State

    @objc
    func setUnidentifiedAccessMode(_ mode: UnidentifiedAccessMode, address: SignalServiceAddress)

    @objc
    func udAccessKey(forAddress address: SignalServiceAddress) -> SMKUDAccessKey?

    @objc
    func udAccess(forAddress address: SignalServiceAddress,
                  requireSyncAccess: Bool,
                  transaction: SDSAnyWriteTransaction) -> OWSUDAccess?

    @objc
    func udSendingAccess(forAddress address: SignalServiceAddress,
                         requireSyncAccess: Bool,
                         senderCertificate: SMKSenderCertificate,
                         transaction: SDSAnyWriteTransaction) -> OWSUDSendingAccess?

    // MARK: Sender Certificate

    // We use completion handlers instead of a promise so that message sending
    // logic can access the strongly typed certificate data.
    @objc
    func ensureSenderCertificate(certificateExpirationPolicy: OWSUDCertificateExpirationPolicy,
                                  success:@escaping (SMKSenderCertificate) -> Void,
                                  failure:@escaping (Error) -> Void)

    @objc
    func removeSenderCertificate(transaction: SDSAnyWriteTransaction)

    // MARK: Unrestricted Access

    @objc
    func shouldAllowUnrestrictedAccessLocal() -> Bool
    @objc
    func setShouldAllowUnrestrictedAccessLocal(_ value: Bool)
}

// MARK: -

@objc
public class OWSUDManagerImpl: NSObject, OWSUDManager {

    @objc
    public let keyValueStore = SDSKeyValueStore(collection: "kUDCollection")
    @objc
    public let phoneNumberAccessStore = SDSKeyValueStore(collection: "kUnidentifiedAccessCollection")
    @objc
    public let uuidAccessStore = SDSKeyValueStore(collection: "kUnidentifiedAccessUUIDCollection")

    // MARK: Local Configuration State

    private let kUDCurrentSenderCertificateKey_Production = "kUDCurrentSenderCertificateKey_Production-uuid"
    private let kUDCurrentSenderCertificateKey_Staging = "kUDCurrentSenderCertificateKey_Staging-uuid"
    private let kUDCurrentSenderCertificateDateKey_Production = "kUDCurrentSenderCertificateDateKey_Production-uuid"
    private let kUDCurrentSenderCertificateDateKey_Staging = "kUDCurrentSenderCertificateDateKey_Staging-uuid"
    private let kUDUnrestrictedAccessKey = "kUDUnrestrictedAccessKey"

    // MARK: Recipient State

    var certificateValidator: SMKCertificateValidator

    @objc
    public required override init() {
        self.certificateValidator = SMKCertificateDefaultValidator(trustRoot: OWSUDManagerImpl.trustRoot())

        super.init()

        SwiftSingletons.register(self)
    }

    @objc public func setup() {
        // TODO: Should we use runNowOrWhenAppDidBecomeReadyPolite?
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            guard self.tsAccountManager.isRegistered else {
                return
            }

            // Any error is silently ignored on startup.
            _ = self.ensureSenderCertificate(certificateExpirationPolicy: .strict)
        }
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(registrationStateDidChange),
                                               name: .registrationStateDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: .OWSApplicationDidBecomeActive,
                                               object: nil)
    }

    @objc
    func registrationStateDidChange() {
        AssertIsOnMainThread()

        guard tsAccountManager.isRegisteredAndReady else {
            return
        }

        // Any error is silently ignored
        _ = ensureSenderCertificate(certificateExpirationPolicy: .strict)
    }

    @objc func didBecomeActive() {
        AssertIsOnMainThread()

        // TODO: Should we use runNowOrWhenAppDidBecomeReadyPolite?
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            guard self.tsAccountManager.isRegistered else {
                return
            }

            // Any error is silently ignored on startup.
            _ = self.ensureSenderCertificate(certificateExpirationPolicy: .strict)
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

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: - Recipient state

    @objc
    public func randomUDAccessKey() -> SMKUDAccessKey {
        return SMKUDAccessKey(randomKeyData: ())
    }

    private func unidentifiedAccessMode(forAddress address: SignalServiceAddress,
                                        transaction: SDSAnyWriteTransaction) -> UnidentifiedAccessMode {
        let defaultValue: UnidentifiedAccessMode =  address.isLocalAddress ? .enabled : .unknown

        let existingUUIDValue: UnidentifiedAccessMode?
        if let uuidString = address.uuidString,
            let existingRawValue = uuidAccessStore.getInt(uuidString, transaction: transaction) {

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
            let existingRawValue = phoneNumberAccessStore.getInt(phoneNumber, transaction: transaction) {

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
                phoneNumberAccessStore.setInt(existingUUIDValue.rawValue, key: address.phoneNumber!, transaction: transaction)
            }

            existingValue = existingUUIDValue
        } else if let existingPhoneNumberValue = existingPhoneNumberValue {
            existingValue = existingPhoneNumberValue

            // We had phone number entry but not UUID, update UUID value
            if let uuidString = address.uuidString {
                uuidAccessStore.setInt(existingPhoneNumberValue.rawValue, key: uuidString, transaction: transaction)
            }
        } else if let existingUUIDValue = existingUUIDValue {
            existingValue = existingUUIDValue

            // We had UUID entry but not phone number, update phone number value
            if let phoneNumber = address.phoneNumber {
                phoneNumberAccessStore.setInt(existingUUIDValue.rawValue, key: phoneNumber, transaction: transaction)
            }
        } else {
            existingValue = nil
        }

        return existingValue ?? defaultValue
    }

    @objc
    public func setUnidentifiedAccessMode(_ mode: UnidentifiedAccessMode, address: SignalServiceAddress) {
        if address.isLocalAddress {
            Logger.info("Setting local UD access mode: \(string(forUnidentifiedAccessMode: mode))")
        }

        databaseStorage.write { (transaction) in
            let oldMode = self.unidentifiedAccessMode(forAddress: address, transaction: transaction)

            if let uuidString = address.uuidString {
                self.uuidAccessStore.setInt(mode.rawValue, key: uuidString, transaction: transaction)
            }

            if let phoneNumber = address.phoneNumber {
                self.phoneNumberAccessStore.setInt(mode.rawValue, key: phoneNumber, transaction: transaction)
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
        let profileKeyData = databaseStorage.read { transaction in
            return self.profileManager.profileKeyData(for: address,
                                                      transaction: transaction)
        }
        guard let profileKey = profileKeyData else {
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

    // Returns the UD access key for sending to a given recipient or fetching a profile
    @objc
    public func udAccess(forAddress address: SignalServiceAddress,
                         requireSyncAccess: Bool,
                         transaction: SDSAnyWriteTransaction) -> OWSUDAccess? {
        if requireSyncAccess {
            guard tsAccountManager.localAddress != nil else {
                if isUDVerboseLoggingEnabled() {
                    Logger.info("UD disabled for \(address), no local number.")
                }
                owsFailDebug("Missing local number.")
                return nil
            }
            if address.isLocalAddress {
                let selfAccessMode = unidentifiedAccessMode(forAddress: address, transaction: transaction)
                guard selfAccessMode != .disabled else {
                    if isUDVerboseLoggingEnabled() {
                        Logger.info("UD disabled for \(address), UD disabled for sync messages.")
                    }
                    return nil
                }
            }
        }

        let accessMode = unidentifiedAccessMode(forAddress: address, transaction: transaction)

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
                if !CurrentAppContext().isRunningTests {
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

    // Returns the UD access key and appropriate sender certificate for sending to a given recipient
    @objc
    public func udSendingAccess(forAddress address: SignalServiceAddress,
                                requireSyncAccess: Bool,
                                senderCertificate: SMKSenderCertificate,
                                transaction: SDSAnyWriteTransaction) -> OWSUDSendingAccess? {
        guard let udAccess = self.udAccess(forAddress: address, requireSyncAccess: requireSyncAccess, transaction: transaction) else {
            return nil
        }
        return OWSUDSendingAccess(udAccess: udAccess, senderCertificate: senderCertificate)
    }

    // MARK: - Sender Certificate

    #if DEBUG
    @objc
    public func hasSenderCertificate() -> Bool {
        return senderCertificate(certificateExpirationPolicy: .permissive) != nil
    }
    #endif

    private func senderCertificate(certificateExpirationPolicy: OWSUDCertificateExpirationPolicy) -> SMKSenderCertificate? {
        var certificateDateValue: Date?
        var certificateDataValue: Data?
        databaseStorage.read { transaction in
            certificateDateValue = self.keyValueStore.getDate(self.senderCertificateDateKey(), transaction: transaction)
            certificateDataValue = self.keyValueStore.getData(self.senderCertificateKey(), transaction: transaction)
        }

        if certificateExpirationPolicy == .strict {
            guard let certificateDate = certificateDateValue else {
                return nil
            }
            guard certificateDate.timeIntervalSinceNow < kDayInterval else {
                // Discard certificates that we obtained more than 24 hours ago.
                return nil
            }
        }

        guard let certificateData = certificateDataValue else {
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

    func setSenderCertificate(certificateData: Data) {
        databaseStorage.write { transaction in
            self.keyValueStore.setDate(Date(), key: self.senderCertificateDateKey(), transaction: transaction)
            self.keyValueStore.setData(certificateData, key: self.senderCertificateKey(), transaction: transaction)
        }
    }

    @objc
    public func removeSenderCertificate(transaction: SDSAnyWriteTransaction) {
        keyValueStore.removeValue(forKey: senderCertificateDateKey(), transaction: transaction)
        keyValueStore.removeValue(forKey: senderCertificateKey(), transaction: transaction)
    }

    private func senderCertificateKey() -> String {
        return TSConstants.isUsingProductionService ? kUDCurrentSenderCertificateKey_Production : kUDCurrentSenderCertificateKey_Staging
    }

    private func senderCertificateDateKey() -> String {
        return TSConstants.isUsingProductionService ? kUDCurrentSenderCertificateDateKey_Production : kUDCurrentSenderCertificateDateKey_Staging
    }

    @objc
    public func ensureSenderCertificate(certificateExpirationPolicy: OWSUDCertificateExpirationPolicy,
                                         success: @escaping (SMKSenderCertificate) -> Void,
                                         failure: @escaping (Error) -> Void) {
        ensureSenderCertificate(certificateExpirationPolicy: certificateExpirationPolicy)
            .done(success)
            .catch(failure)
    }

    public func ensureSenderCertificate(certificateExpirationPolicy: OWSUDCertificateExpirationPolicy) -> Promise<SMKSenderCertificate> {
        // If there is a valid cached sender certificate, use that.
        if let certificate = senderCertificate(certificateExpirationPolicy: certificateExpirationPolicy) {
            return Promise.value(certificate)
        }

        return firstly {
            requestSenderCertificate()
        }.map { (certificate: SMKSenderCertificate) in
            self.setSenderCertificate(certificateData: certificate.serializedData)
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
        guard certificate.senderDeviceId == tsAccountManager.storedDeviceId() else {
            Logger.warn("Sender certificate has incorrect device ID")
            return false
        }

        guard certificate.senderAddress.e164 == tsAccountManager.localNumber else {
            Logger.warn("Sender certificate has incorrect phone number")
            return false
        }

        guard certificate.senderAddress.uuid == nil || certificate.senderAddress.uuid == tsAccountManager.localUuid else {
            Logger.warn("Sender certificate has incorrect UUID")
            return false
        }

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
        guard let trustRootData = NSData(fromBase64String: TSConstants.kUDTrustRoot) else {
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
        return databaseStorage.read { transaction in
            self.keyValueStore.getBool(self.kUDUnrestrictedAccessKey, defaultValue: false, transaction: transaction)
        }
    }

    @objc
    public func setShouldAllowUnrestrictedAccessLocal(_ value: Bool) {
        databaseStorage.write { transaction in
            self.keyValueStore.setBool(value, key: self.kUDUnrestrictedAccessKey, transaction: transaction)
        }

        // Try to update the account attributes to reflect this change.
        firstly {
            tsAccountManager.updateAccountAttributes()
        }.catch { error in
            Logger.warn("Error: \(error)")
        }
    }
}
