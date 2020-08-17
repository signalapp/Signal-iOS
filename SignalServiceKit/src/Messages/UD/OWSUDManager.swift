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

extension UnidentifiedAccessMode: CustomStringConvertible {
    public var description: String {
        switch self {
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

    @objc func trustRoot() -> ECPublicKey

    @objc func isUDVerboseLoggingEnabled() -> Bool

    // MARK: - Recipient State

    @objc
    func setUnidentifiedAccessMode(_ mode: UnidentifiedAccessMode, address: SignalServiceAddress)

    @objc
    func udAccessKey(forAddress address: SignalServiceAddress) -> SMKUDAccessKey?

    @objc
    func udAccess(forAddress address: SignalServiceAddress, requireSyncAccess: Bool) -> OWSUDAccess?

    @objc
    func udSendingAccess(forAddress address: SignalServiceAddress,
                         requireSyncAccess: Bool,
                         senderCertificate: SMKSenderCertificate) -> OWSUDSendingAccess?

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

    // To avoid deadlock, never open a database transaction while
    // unfairLock is acquired.
    private let unfairLock = UnfairLock()

    // These two caches should only be accessed using unfairLock.
    private var phoneNumberAccessCache = [String: UnidentifiedAccessMode]()
    private var uuidAccessCache = [UUID: UnidentifiedAccessMode]()

    @objc
    public required override init() {
        self.certificateValidator = SMKCertificateDefaultValidator(trustRoot: OWSUDManagerImpl.trustRoot())

        super.init()

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            self.warmCaches()
        }
        AppReadiness.runNowOrWhenAppDidBecomeReady {
            self.setup()
        }
    }

    private func warmCaches() {
        let parseUnidentifiedAccessMode = { (anyValue: Any) -> UnidentifiedAccessMode? in
            guard let nsNumber = anyValue as? NSNumber else {
                owsFailDebug("Invalid value.")
                return nil
            }
            guard let value = UnidentifiedAccessMode(rawValue: nsNumber.intValue) else {
                owsFailDebug("Couldn't parse mode value: (nsNumber.intValue).")
                return nil
            }
            return value
        }

        databaseStorage.read { transaction in
            self.unfairLock.withLock {
                self.phoneNumberAccessStore.enumerateKeysAndObjects(transaction: transaction) { (phoneNumber: String, anyValue: Any, _) in
                    guard let mode = parseUnidentifiedAccessMode(anyValue) else {
                        return
                    }
                    self.phoneNumberAccessCache[phoneNumber] = mode
                }
                self.uuidAccessStore.enumerateKeysAndObjects(transaction: transaction) { (uuidString: String, anyValue: Any, _) in
                    guard let uuid = UUID(uuidString: uuidString) else {
                        owsFailDebug("Invalid uuid: \(uuidString)")
                        return
                    }
                    guard let mode = parseUnidentifiedAccessMode(anyValue) else {
                        return
                    }
                    self.uuidAccessCache[uuid] = mode
                }
            }
        }
    }

    private func setup() {
        owsAssertDebug(AppReadiness.isAppReady)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(registrationStateDidChange),
                                               name: .registrationStateDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: .OWSApplicationDidBecomeActive,
                                               object: nil)

        // We can fill in any missing sender certificate async;
        // message sending will fill in the sender certificate sooner
        // if it needs it.
        DispatchQueue.global().async {
            // Any error is silently ignored.
            _ = self.ensureSenderCertificate(certificateExpirationPolicy: .strict)
        }
    }

    @objc
    func registrationStateDidChange() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        // Any error is silently ignored.
        _ = ensureSenderCertificate(certificateExpirationPolicy: .strict)
    }

    @objc
    func didBecomeActive() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        // Any error is silently ignored.
        _ = self.ensureSenderCertificate(certificateExpirationPolicy: .strict)
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

    private var bulkProfileFetch: BulkProfileFetch {
        return SSKEnvironment.shared.bulkProfileFetch
    }

    // MARK: - Recipient state

    @objc
    public func randomUDAccessKey() -> SMKUDAccessKey {
        return SMKUDAccessKey(randomKeyData: ())
    }

    private func unidentifiedAccessMode(forAddress address: SignalServiceAddress) -> UnidentifiedAccessMode {

        // Read from caches.
        var existingUUIDValue: UnidentifiedAccessMode?
        var existingPhoneNumberValue: UnidentifiedAccessMode?
        unfairLock.withLock {
            if let uuid = address.uuid {
                existingUUIDValue = self.uuidAccessCache[uuid]
            }
            if let phoneNumber = address.phoneNumber {
                existingPhoneNumberValue = self.phoneNumberAccessCache[phoneNumber]
            }
        }

        // Resolve current value; determine if we need to update cache and database.
        let existingValue: UnidentifiedAccessMode?
        var shouldUpdateValues = false
        if let existingUUIDValue = existingUUIDValue, let existingPhoneNumberValue = existingPhoneNumberValue {

            // If UUID and Phone Number setting don't align, defer to UUID and update phone number
            if existingPhoneNumberValue != existingUUIDValue {
                Logger.warn("Unexpected UD value mismatch; updating UD state.")
                shouldUpdateValues = true
                existingValue = .disabled

                // Fetch profile for this user to determine current UD state.
                DispatchQueue.global().async {
                    self.bulkProfileFetch.fetchProfile(address: address)
                }
            } else {
                existingValue = existingUUIDValue
            }
        } else if let existingPhoneNumberValue = existingPhoneNumberValue {
            existingValue = existingPhoneNumberValue

            // We had phone number entry but not UUID, update UUID value
            if nil != address.uuidString {
                shouldUpdateValues = true
            }
        } else if let existingUUIDValue = existingUUIDValue {
            existingValue = existingUUIDValue

            // We had UUID entry but not phone number, update phone number value
            if nil != address.phoneNumber {
                shouldUpdateValues = true
            }
        } else {
            existingValue = nil
        }

        if let existingValue = existingValue, shouldUpdateValues {
            setUnidentifiedAccessMode(existingValue, address: address)
        }

        let defaultValue: UnidentifiedAccessMode =  address.isLocalAddress ? .enabled : .unknown
        return existingValue ?? defaultValue
    }

    @objc
    public func setUnidentifiedAccessMode(_ mode: UnidentifiedAccessMode, address: SignalServiceAddress) {
        if address.isLocalAddress {
            Logger.info("Setting local UD access mode: \(mode)")
        }

        // Update cache immediately.
        var didChange = false
        self.unfairLock.withLock {
            if let uuid = address.uuid {
                if self.uuidAccessCache[uuid] != mode {
                    didChange = true
                }
                self.uuidAccessCache[uuid] = mode
            }
            if let phoneNumber = address.phoneNumber {
                if self.phoneNumberAccessCache[phoneNumber] != mode {
                    didChange = true
                }
                self.phoneNumberAccessCache[phoneNumber] = mode
            }
        }
        guard didChange else {
            return
        }
        // Update database async.
        databaseStorage.asyncWrite { transaction in
            if let uuid = address.uuid {
                self.uuidAccessStore.setInt(mode.rawValue, key: uuid.uuidString, transaction: transaction)
            }
            if let phoneNumber = address.phoneNumber {
                self.phoneNumberAccessStore.setInt(mode.rawValue, key: phoneNumber, transaction: transaction)
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
    public func udAccess(forAddress address: SignalServiceAddress, requireSyncAccess: Bool) -> OWSUDAccess? {
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
                // Not an error.
                // We can only use UD if the user has UD enabled _and_
                // we know their profile key.
                Logger.warn("Missing profile key for UD-enabled user: \(address).")
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
                                senderCertificate: SMKSenderCertificate) -> OWSUDSendingAccess? {
        guard let udAccess = self.udAccess(forAddress: address, requireSyncAccess: requireSyncAccess) else {
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
        guard tsAccountManager.isRegisteredAndReady else {
            // We don't want to assert but we should log and fail.
            return Promise(error: OWSGenericError("Not registered and ready."))
        }

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
