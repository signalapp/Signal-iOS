//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Curve25519Kit
import SignalCoreKit
import LibSignalClient

public enum OWSUDError: Error {
    case assertionError(description: String)
    case invalidData(description: String)
}

// MARK: -

extension OWSUDError: IsRetryableProvider {
    public var isRetryableProvider: Bool {
        switch self {
        case .assertionError, .invalidData:
            return false
        }
    }
}

// MARK: -

@objc
public enum OWSUDCertificateExpirationPolicy: Int {
    // We want to try to rotate the sender certificate
    // on a frequent basis, but we don't want to block
    // sending on this.
    case strict
    case permissive
}

// MARK: -

@objc
public enum UnidentifiedAccessMode: Int {
    case unknown
    case enabled
    case disabled
    case unrestricted
}

// MARK: -

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

// MARK: -

@objc
public class OWSUDAccess: NSObject {
    @objc
    public let udAccessKey: SMKUDAccessKey
    public var senderKeyUDAccessKey: SMKUDAccessKey {
        // If unrestricted, we use a zeroed out key instead of a random key
        // This ensures we don't scribble over the rest of our composite key when talking to the multi_recipient endpoint
        udAccessMode == .unrestricted ? .zeroedKey : udAccessKey
    }

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

// MARK: -

@objc
public class SenderCertificates: NSObject {
    let defaultCert: SenderCertificate
    let uuidOnlyCert: SenderCertificate
    init(defaultCert: SenderCertificate, uuidOnlyCert: SenderCertificate) {
        self.defaultCert = defaultCert
        self.uuidOnlyCert = uuidOnlyCert
    }
}

// MARK: -

@objc
public class OWSUDSendingAccess: NSObject {

    @objc
    public let udAccess: OWSUDAccess

    public let senderCertificate: SenderCertificate

    init(udAccess: OWSUDAccess, senderCertificate: SenderCertificate) {
        self.udAccess = udAccess
        self.senderCertificate = senderCertificate
    }
}

// MARK: -

@objc
public protocol OWSUDManager: AnyObject {
    @objc
    var keyValueStore: SDSKeyValueStore { get }
    @objc
    var phoneNumberAccessStore: SDSKeyValueStore { get }
    @objc
    var uuidAccessStore: SDSKeyValueStore { get }

    @objc
    func warmCaches()

    @objc
    var trustRoot: ECPublicKey { get }

    @objc
    func isUDVerboseLoggingEnabled() -> Bool

    // MARK: - Recipient State

    @objc
    func setUnidentifiedAccessMode(_ mode: UnidentifiedAccessMode, address: SignalServiceAddress)

    @objc
    func udAccessKey(forAddress address: SignalServiceAddress) -> SMKUDAccessKey?

    @objc
    func udAccess(forAddress address: SignalServiceAddress, requireSyncAccess: Bool) -> OWSUDAccess?

    @objc
    func udSendingAccess(
        for serviceId: ServiceIdObjC,
        requireSyncAccess: Bool,
        senderCertificates: SenderCertificates
    ) -> OWSUDSendingAccess?

    @objc
    func storySendingAccess(for serviceId: ServiceIdObjC, senderCertificates: SenderCertificates) -> OWSUDSendingAccess

    @objc
    func fetchAllAciUakPairs(tx: SDSAnyReadTransaction) -> [AciObjC: SMKUDAccessKey]

    // MARK: Sender Certificate

    // We use completion handlers instead of a promise so that message sending
    // logic can access the strongly typed certificate data.
    @objc
    func ensureSenderCertificates(certificateExpirationPolicy: OWSUDCertificateExpirationPolicy,
                                  success: @escaping (SenderCertificates) -> Void,
                                  failure: @escaping (Error) -> Void)

    @objc
    func removeSenderCertificates(transaction: SDSAnyWriteTransaction)

    // MARK: Unrestricted Access

    @objc
    func shouldAllowUnrestrictedAccessLocal() -> Bool

    func shouldAllowUnrestrictedAccessLocal(transaction: SDSAnyReadTransaction) -> Bool

    @objc
    func setShouldAllowUnrestrictedAccessLocal(_ value: Bool)

    var phoneNumberSharingMode: PhoneNumberSharingMode { get }

    func setPhoneNumberSharingMode(
        _ mode: PhoneNumberSharingMode,
        updateStorageService: Bool,
        transaction: GRDBWriteTransaction
    )
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

    // These keys contain the word "Production" for historical reasons, but
    // they store sender certificates in both production & staging builds.
    private let kUDCurrentSenderCertificateKey = "kUDCurrentSenderCertificateKey_Production-uuid"
    private let kUDCurrentSenderCertificateDateKey = "kUDCurrentSenderCertificateDateKey_Production-uuid"

    private let kUDUnrestrictedAccessKey = "kUDUnrestrictedAccessKey"

    // MARK: Recipient State

    // Exposed for testing
    public internal(set) var trustRoot: ECPublicKey

    // To avoid deadlock, never open a database transaction while
    // unfairLock is acquired.
    private let unfairLock = UnfairLock()

    // These two caches should only be accessed using unfairLock.
    //
    // TODO: We might not want to use comprehensive caches here.
    private var phoneNumberAccessCache = [String: UnidentifiedAccessMode]()
    // PNI TODO: Change this type to Aci or ServiceId.
    private var uuidAccessCache = [UUID: UnidentifiedAccessMode]()

    @objc
    public required override init() {
        self.trustRoot = OWSUDManagerImpl.trustRoot()

        super.init()

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            self.setup()
        }
    }

    @objc
    public func warmCaches() {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)

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
            self.cachePhoneNumberSharingMode(transaction: transaction.unwrapGrdbRead)

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

                if DebugFlags.internalLogging {
                    Logger.info("phoneNumberAccessCache: \(phoneNumberAccessCache.count), uuidAccessCache: \(uuidAccessCache.count), ")
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
            _ = self.ensureSenderCertificates(certificateExpirationPolicy: .strict)
        }
    }

    @objc
    func registrationStateDidChange() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        // Any error is silently ignored.
        _ = ensureSenderCertificates(certificateExpirationPolicy: .strict)
    }

    @objc
    func didBecomeActive() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        // Any error is silently ignored.
        _ = ensureSenderCertificates(certificateExpirationPolicy: .strict)
    }

    // MARK: -

    @objc
    public func isUDVerboseLoggingEnabled() -> Bool {
        return false
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
                self.bulkProfileFetch.fetchProfile(address: address)
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

    public func fetchAllAciUakPairs(tx: SDSAnyReadTransaction) -> [AciObjC: SMKUDAccessKey] {
        let acis = self.unfairLock.withLock {
            self.uuidAccessCache.compactMap { (serviceId, mode) -> Aci? in
                switch mode {
                case .enabled, .unrestricted, .unknown:
                    return Aci(fromUUID: serviceId)
                case .disabled:
                    return nil
                }
            }
        }
        var result = [AciObjC: SMKUDAccessKey]()
        for aci in acis {
            result[AciObjC(aci)] = udAccessKey(for: SignalServiceAddress(aci), tx: tx)
        }
        return result
    }

    // Returns the UD access key for a given recipient
    // if we have a valid profile key for them.
    @objc
    public func udAccessKey(forAddress address: SignalServiceAddress) -> SMKUDAccessKey? {
        return databaseStorage.read { tx in udAccessKey(for: address, tx: tx) }
    }

    private func udAccessKey(for address: SignalServiceAddress, tx: SDSAnyReadTransaction) -> SMKUDAccessKey? {
        guard let profileKey = profileManager.profileKeyData(for: address, transaction: tx) else {
            return nil
        }
        do {
            return try SMKUDAccessKey(profileKey: profileKey)
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
    public func udSendingAccess(
        for serviceId: ServiceIdObjC,
        requireSyncAccess: Bool,
        senderCertificates: SenderCertificates
    ) -> OWSUDSendingAccess? {
        let address = SignalServiceAddress(serviceId.wrappedValue)
        guard let udAccess = self.udAccess(forAddress: address, requireSyncAccess: requireSyncAccess) else {
            return nil
        }
        return udSendingAccess(for: serviceId.wrappedValue, udAccess: udAccess, senderCertificates: senderCertificates)
    }

    @objc
    public func storySendingAccess(for serviceId: ServiceIdObjC, senderCertificates: SenderCertificates) -> OWSUDSendingAccess {
        let udAccess = OWSUDAccess(udAccessKey: randomUDAccessKey(), udAccessMode: .unrestricted, isRandomKey: true)
        return udSendingAccess(for: serviceId.wrappedValue, udAccess: udAccess, senderCertificates: senderCertificates)
    }

    private func udSendingAccess(
        for serviceId: ServiceId,
        udAccess: OWSUDAccess,
        senderCertificates: SenderCertificates
    ) -> OWSUDSendingAccess {
        databaseStorage.read { transaction in
            let shouldSharePhoneNumber: Bool
            switch phoneNumberSharingMode {
            case .everybody:
                shouldSharePhoneNumber = true
            case .nobody:
                shouldSharePhoneNumber = identityManager.shouldSharePhoneNumber(with: serviceId, transaction: transaction)
            }
            return OWSUDSendingAccess(
                udAccess: udAccess,
                senderCertificate: shouldSharePhoneNumber ? senderCertificates.defaultCert : senderCertificates.uuidOnlyCert
            )
        }
    }

    // MARK: - Sender Certificate

    #if TESTABLE_BUILD
    @objc
    public func hasSenderCertificates() -> Bool {
        return senderCertificate(uuidOnly: true, certificateExpirationPolicy: .permissive) != nil
            && senderCertificate(uuidOnly: false, certificateExpirationPolicy: .permissive) != nil
    }
    #endif

    private func senderCertificate(uuidOnly: Bool, certificateExpirationPolicy: OWSUDCertificateExpirationPolicy) -> SenderCertificate? {
        var certificateDateValue: Date?
        var certificateDataValue: Data?
        databaseStorage.read { transaction in
            certificateDateValue = self.keyValueStore.getDate(self.senderCertificateDateKey(uuidOnly: uuidOnly), transaction: transaction)
            certificateDataValue = self.keyValueStore.getData(self.senderCertificateKey(uuidOnly: uuidOnly), transaction: transaction)
        }

        if certificateExpirationPolicy == .strict {
            guard let certificateDate = certificateDateValue else {
                return nil
            }
            guard -certificateDate.timeIntervalSinceNow < kDayInterval else {
                // Discard certificates that we obtained more than 24 hours ago.
                return nil
            }
        }

        guard let certificateData = certificateDataValue else {
            return nil
        }

        do {
            let certificate = try SenderCertificate(certificateData)

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

    func setSenderCertificate(uuidOnly: Bool, certificateData: Data) {
        databaseStorage.write { transaction in
            self.keyValueStore.setDate(Date(), key: self.senderCertificateDateKey(uuidOnly: uuidOnly), transaction: transaction)
            self.keyValueStore.setData(certificateData, key: self.senderCertificateKey(uuidOnly: uuidOnly), transaction: transaction)
        }
    }

    @objc
    public func removeSenderCertificates(transaction: SDSAnyWriteTransaction) {
        keyValueStore.removeValue(forKey: senderCertificateDateKey(uuidOnly: true), transaction: transaction)
        keyValueStore.removeValue(forKey: senderCertificateKey(uuidOnly: true), transaction: transaction)
        keyValueStore.removeValue(forKey: senderCertificateDateKey(uuidOnly: false), transaction: transaction)
        keyValueStore.removeValue(forKey: senderCertificateKey(uuidOnly: false), transaction: transaction)
    }

    private func senderCertificateKey(uuidOnly: Bool) -> String {
        let baseKey = kUDCurrentSenderCertificateKey
        if uuidOnly {
            return "\(baseKey)-withoutPhoneNumber"
        } else {
            return baseKey
        }
    }

    private func senderCertificateDateKey(uuidOnly: Bool) -> String {
        let baseKey = kUDCurrentSenderCertificateDateKey
        if uuidOnly {
            return "\(baseKey)-withoutPhoneNumber"
        } else {
            return baseKey
        }
    }

    @objc
    public func ensureSenderCertificates(certificateExpirationPolicy: OWSUDCertificateExpirationPolicy,
                                         success: @escaping (SenderCertificates) -> Void,
                                         failure: @escaping (Error) -> Void) {
        firstly(on: DispatchQueue.global()) {
            self.ensureSenderCertificates(certificateExpirationPolicy: certificateExpirationPolicy)
        }.done(on: DispatchQueue.global()) { senderCertificates in
            success(senderCertificates)
        }.catch(on: DispatchQueue.global()) { error in
            failure(error)
        }
    }

    public func ensureSenderCertificates(certificateExpirationPolicy: OWSUDCertificateExpirationPolicy) -> Promise<SenderCertificates> {
        guard tsAccountManager.isRegisteredAndReady else {
            // We don't want to assert but we should log and fail.
            return Promise(error: OWSGenericError("Not registered and ready."))
        }
        let defaultPromise = ensureSenderCertificate(uuidOnly: false, certificateExpirationPolicy: certificateExpirationPolicy)
        let uuidOnlyPromise = ensureSenderCertificate(uuidOnly: true, certificateExpirationPolicy: certificateExpirationPolicy)
        return firstly(on: DispatchQueue.global()) {
            Promise.when(fulfilled: defaultPromise, uuidOnlyPromise)
        }.map(on: DispatchQueue.global()) { defaultCert, uuidOnlyCert in
            return SenderCertificates(defaultCert: defaultCert, uuidOnlyCert: uuidOnlyCert)
        }
    }

    public func ensureSenderCertificate(uuidOnly: Bool, certificateExpirationPolicy: OWSUDCertificateExpirationPolicy) -> Promise<SenderCertificate> {
        // If there is a valid cached sender certificate, use that.
        if let certificate = senderCertificate(uuidOnly: uuidOnly, certificateExpirationPolicy: certificateExpirationPolicy) {
            return Promise.value(certificate)
        }

        return firstly(on: DispatchQueue.global()) {
            self.requestSenderCertificate(uuidOnly: uuidOnly)
        }.map(on: DispatchQueue.global()) { (certificate: SenderCertificate) in
            self.setSenderCertificate(uuidOnly: uuidOnly, certificateData: Data(certificate.serialize()))
            return certificate
        }
    }

    private func requestSenderCertificate(uuidOnly: Bool) -> Promise<SenderCertificate> {
        return firstly(on: DispatchQueue.global()) {
            SignalServiceRestClient().requestUDSenderCertificate(uuidOnly: uuidOnly)
        }.map(on: DispatchQueue.global()) { (certificateData: Data) -> SenderCertificate in
            let certificate = try SenderCertificate(certificateData)

            guard self.isValidCertificate(certificate) else {
                throw OWSUDError.invalidData(description: "Invalid sender certificate returned by server")
            }

            return certificate
        }.recover(on: DispatchQueue.global()) { error -> Promise<SenderCertificate> in
            throw error
        }
    }

    private func isValidCertificate(_ certificate: SenderCertificate) -> Bool {
        let sender = certificate.sender
        guard sender.deviceId == tsAccountManager.storedDeviceId else {
            Logger.warn("Sender certificate has incorrect device ID")
            return false
        }

        let localIdentifiers = tsAccountManager.localIdentifiers

        guard sender.e164 == nil || sender.e164 == localIdentifiers?.phoneNumber else {
            Logger.warn("Sender certificate has incorrect phone number")
            return false
        }

        guard sender.senderAci == localIdentifiers!.aci else {
            Logger.warn("Sender certificate has incorrect ACI")
            return false
        }

        // Ensure that the certificate will not expire in the next hour.
        // We want a threshold long enough to ensure that any outgoing message
        // sends will complete before the expiration.
        let nowMs = NSDate.ows_millisecondTimeStamp()
        let anHourFromNowMs = nowMs + kHourInMs

        if case .some(true) = try? certificate.validate(trustRoot: trustRoot.key, time: anHourFromNowMs) {
            return true
        }
        Logger.error("Invalid certificate")
        return false
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
            return self.shouldAllowUnrestrictedAccessLocal(transaction: transaction)
        }
    }

    public func shouldAllowUnrestrictedAccessLocal(transaction: SDSAnyReadTransaction) -> Bool {
        return self.keyValueStore.getBool(self.kUDUnrestrictedAccessKey, defaultValue: false, transaction: transaction)
    }

    @objc
    public func setShouldAllowUnrestrictedAccessLocal(_ value: Bool) {
        databaseStorage.write { transaction in
            self.keyValueStore.setBool(value, key: self.kUDUnrestrictedAccessKey, transaction: transaction)
        }

        // Try to update the account attributes to reflect this change.
        firstly(on: DispatchQueue.global()) {
            Self.tsAccountManager.updateAccountAttributes()
        }.catch(on: DispatchQueue.global()) { error in
            Logger.warn("Error: \(error)")
        }
    }

    // MARK: - Phone Number Sharing

    private static var phoneNumberSharingModeKey: String { "phoneNumberSharingMode" }
    private var phoneNumberSharingModeCached = AtomicOptional<PhoneNumberSharingMode>(nil)

    public var phoneNumberSharingMode: PhoneNumberSharingMode {
        guard FeatureFlags.phoneNumberSharing else { return .everybody }
        return phoneNumberSharingModeCached.get() ?? .everybody
    }

    private func cachePhoneNumberSharingMode(transaction: GRDBReadTransaction) {
        guard let rawMode = keyValueStore.getInt(Self.phoneNumberSharingModeKey, transaction: transaction.asAnyRead),
            let mode = PhoneNumberSharingMode(rawValue: rawMode) else { return }
        phoneNumberSharingModeCached.set(mode)
    }

    public func setPhoneNumberSharingMode(
        _ mode: PhoneNumberSharingMode,
        updateStorageService: Bool,
        transaction: GRDBWriteTransaction
    ) {
        guard FeatureFlags.phoneNumberSharing else { return }

        keyValueStore.setInt(mode.rawValue, key: Self.phoneNumberSharingModeKey, transaction: transaction.asAnyWrite)
        phoneNumberSharingModeCached.set(mode)

        if updateStorageService {
            transaction.addSyncCompletion {
                Self.storageServiceManager.recordPendingLocalAccountUpdates()
            }
        }
    }
}

// MARK: -

/// These are persisted to disk, so they must remain stable.
@objc
public enum PhoneNumberSharingMode: Int {
    case everybody = 0
    case nobody = 2
}
