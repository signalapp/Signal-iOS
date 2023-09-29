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

public enum OWSUDCertificateExpirationPolicy: Int {
    // We want to try to rotate the sender certificate
    // on a frequent basis, but we don't want to block
    // sending on this.
    case strict
    case permissive
}

// MARK: -

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

public class OWSUDAccess: NSObject {
    public let udAccessKey: SMKUDAccessKey
    public var senderKeyUDAccessKey: SMKUDAccessKey {
        // If unrestricted, we use a zeroed out key instead of a random key
        // This ensures we don't scribble over the rest of our composite key when talking to the multi_recipient endpoint
        udAccessMode == .unrestricted ? .zeroedKey : udAccessKey
    }

    public let udAccessMode: UnidentifiedAccessMode

    public let isRandomKey: Bool

    public required init(udAccessKey: SMKUDAccessKey,
                         udAccessMode: UnidentifiedAccessMode,
                         isRandomKey: Bool) {
        self.udAccessKey = udAccessKey
        self.udAccessMode = udAccessMode
        self.isRandomKey = isRandomKey
    }
}

// MARK: -

public class SenderCertificates: NSObject {
    let defaultCert: SenderCertificate
    let uuidOnlyCert: SenderCertificate
    init(defaultCert: SenderCertificate, uuidOnlyCert: SenderCertificate) {
        self.defaultCert = defaultCert
        self.uuidOnlyCert = uuidOnlyCert
    }
}

// MARK: -

public class OWSUDSendingAccess: NSObject {

    public let udAccess: OWSUDAccess

    public let senderCertificate: SenderCertificate

    init(udAccess: OWSUDAccess, senderCertificate: SenderCertificate) {
        self.udAccess = udAccess
        self.senderCertificate = senderCertificate
    }
}

// MARK: -

public protocol OWSUDManager {

    var trustRoot: ECPublicKey { get }

    // MARK: - Recipient State

    func setUnidentifiedAccessMode(_ mode: UnidentifiedAccessMode, for serviceId: ServiceId, tx: SDSAnyWriteTransaction)

    func udAccessKey(for serviceId: ServiceId, tx: SDSAnyReadTransaction) -> SMKUDAccessKey?

    func udAccess(for serviceId: ServiceId, tx: SDSAnyReadTransaction) -> OWSUDAccess?

    func storyUdAccess() -> OWSUDAccess

    func fetchAllAciUakPairs(tx: SDSAnyReadTransaction) -> [Aci: SMKUDAccessKey]

    // MARK: Sender Certificate

    func ensureSenderCertificates(certificateExpirationPolicy: OWSUDCertificateExpirationPolicy) -> Promise<SenderCertificates>

    func removeSenderCertificates(transaction: SDSAnyWriteTransaction)
    func removeSenderCertificates(tx: DBWriteTransaction)

    // MARK: Unrestricted Access

    func shouldAllowUnrestrictedAccessLocal() -> Bool

    func shouldAllowUnrestrictedAccessLocal(transaction: SDSAnyReadTransaction) -> Bool

    func setShouldAllowUnrestrictedAccessLocal(_ value: Bool)

    func phoneNumberSharingMode(tx: SDSAnyReadTransaction) -> PhoneNumberSharingMode

    func setPhoneNumberSharingMode(
        _ mode: PhoneNumberSharingMode,
        updateStorageService: Bool,
        tx: SDSAnyWriteTransaction
    )
}

// MARK: -

public class OWSUDManagerImpl: NSObject, OWSUDManager {

    private let keyValueStore = SDSKeyValueStore(collection: "kUDCollection")
    private let serviceIdAccessStore = SDSKeyValueStore(collection: "kUnidentifiedAccessUUIDCollection")

    // MARK: Local Configuration State

    // These keys contain the word "Production" for historical reasons, but
    // they store sender certificates in both production & staging builds.
    private let kUDCurrentSenderCertificateKey = "kUDCurrentSenderCertificateKey_Production-uuid"
    private let kUDCurrentSenderCertificateDateKey = "kUDCurrentSenderCertificateDateKey_Production-uuid"

    private let kUDUnrestrictedAccessKey = "kUDUnrestrictedAccessKey"

    // MARK: Recipient State

    // Exposed for testing
    public internal(set) var trustRoot: ECPublicKey

    public required override init() {
        self.trustRoot = OWSUDManagerImpl.trustRoot()

        super.init()

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenAppDidBecomeReadySync {
            self.setup()
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
    private func registrationStateDidChange() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        // Any error is silently ignored.
        _ = ensureSenderCertificates(certificateExpirationPolicy: .strict)
    }

    @objc
    private func didBecomeActive() {
        AssertIsOnMainThread()
        owsAssertDebug(AppReadiness.isAppReady)

        // Any error is silently ignored.
        _ = ensureSenderCertificates(certificateExpirationPolicy: .strict)
    }

    // MARK: - Recipient state

    private func randomUDAccessKey() -> SMKUDAccessKey {
        return SMKUDAccessKey(randomKeyData: ())
    }

    private func unidentifiedAccessMode(for serviceId: ServiceId, tx: SDSAnyReadTransaction) -> UnidentifiedAccessMode {
        let existingValue: UnidentifiedAccessMode? = {
            guard let rawValue = serviceIdAccessStore.getInt(serviceId.serviceIdUppercaseString, transaction: tx) else {
                return nil
            }
            return UnidentifiedAccessMode(rawValue: rawValue)
        }()
        return existingValue ?? .unknown
    }

    public func setUnidentifiedAccessMode(
        _ mode: UnidentifiedAccessMode,
        for serviceId: ServiceId,
        tx: SDSAnyWriteTransaction
    ) {
        serviceIdAccessStore.setInt(mode.rawValue, key: serviceId.serviceIdUppercaseString, transaction: tx)
    }

    public func fetchAllAciUakPairs(tx: SDSAnyReadTransaction) -> [Aci: SMKUDAccessKey] {
        let acis: [Aci] = serviceIdAccessStore.allKeys(transaction: tx).compactMap { serviceIdString in
            guard let aci = try? ServiceId.parseFrom(serviceIdString: serviceIdString) as? Aci else {
                return nil
            }
            switch unidentifiedAccessMode(for: aci, tx: tx) {
            case .enabled, .unrestricted, .unknown:
                return aci
            case .disabled:
                return nil
            }
        }
        var result = [Aci: SMKUDAccessKey]()
        for aci in acis {
            result[aci] = udAccessKey(for: aci, tx: tx)
        }
        return result
    }

    // Returns the UD access key for a given recipient
    // if we have a valid profile key for them.
    public func udAccessKey(for serviceId: ServiceId, tx: SDSAnyReadTransaction) -> SMKUDAccessKey? {
        guard let profileKey = profileManager.profileKeyData(for: SignalServiceAddress(serviceId), transaction: tx) else {
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
    public func udAccess(for serviceId: ServiceId, tx: SDSAnyReadTransaction) -> OWSUDAccess? {
        let accessMode = unidentifiedAccessMode(for: serviceId, tx: tx)

        switch accessMode {
        case .unrestricted:
            // Unrestricted users should use a random key.
            let udAccessKey = randomUDAccessKey()
            return OWSUDAccess(udAccessKey: udAccessKey, udAccessMode: accessMode, isRandomKey: true)
        case .unknown:
            // Unknown users should use a derived key if possible,
            // and otherwise use a random key.
            if let udAccessKey = udAccessKey(for: serviceId, tx: tx) {
                return OWSUDAccess(udAccessKey: udAccessKey, udAccessMode: accessMode, isRandomKey: false)
            } else {
                let udAccessKey = randomUDAccessKey()
                return OWSUDAccess(udAccessKey: udAccessKey, udAccessMode: accessMode, isRandomKey: true)
            }
        case .enabled:
            guard let udAccessKey = udAccessKey(for: serviceId, tx: tx) else {
                // Not an error.
                // We can only use UD if the user has UD enabled _and_
                // we know their profile key.
                Logger.warn("Missing profile key for UD-enabled user: \(serviceId).")
                return nil
            }
            return OWSUDAccess(udAccessKey: udAccessKey, udAccessMode: accessMode, isRandomKey: false)
        case .disabled:
            return nil
        }
    }

    public func storyUdAccess() -> OWSUDAccess {
        return OWSUDAccess(udAccessKey: randomUDAccessKey(), udAccessMode: .unrestricted, isRandomKey: true)
    }

    // MARK: - Sender Certificate

    #if TESTABLE_BUILD
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

    public func removeSenderCertificates(transaction: SDSAnyWriteTransaction) {
        keyValueStore.removeValue(forKey: senderCertificateDateKey(uuidOnly: true), transaction: transaction)
        keyValueStore.removeValue(forKey: senderCertificateKey(uuidOnly: true), transaction: transaction)
        keyValueStore.removeValue(forKey: senderCertificateDateKey(uuidOnly: false), transaction: transaction)
        keyValueStore.removeValue(forKey: senderCertificateKey(uuidOnly: false), transaction: transaction)
    }

    public func removeSenderCertificates(tx: DBWriteTransaction) {
        removeSenderCertificates(transaction: SDSDB.shimOnlyBridge(tx))
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

    public func shouldAllowUnrestrictedAccessLocal() -> Bool {
        return databaseStorage.read { transaction in
            return self.shouldAllowUnrestrictedAccessLocal(transaction: transaction)
        }
    }

    public func shouldAllowUnrestrictedAccessLocal(transaction: SDSAnyReadTransaction) -> Bool {
        return self.keyValueStore.getBool(self.kUDUnrestrictedAccessKey, defaultValue: false, transaction: transaction)
    }

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

    public func phoneNumberSharingMode(tx: SDSAnyReadTransaction) -> PhoneNumberSharingMode {
        let result: PhoneNumberSharingMode? = {
            guard FeatureFlags.phoneNumberSharing else {
                return nil
            }
            guard let rawMode = keyValueStore.getInt(Self.phoneNumberSharingModeKey, transaction: tx) else {
                return nil
            }
            return PhoneNumberSharingMode(rawValue: rawMode)
        }()
        return result ?? .everybody
    }

    public func setPhoneNumberSharingMode(
        _ mode: PhoneNumberSharingMode,
        updateStorageService: Bool,
        tx: SDSAnyWriteTransaction
    ) {
        guard FeatureFlags.phoneNumberSharing else {
            return
        }

        keyValueStore.setInt(mode.rawValue, key: Self.phoneNumberSharingModeKey, transaction: tx)

        if updateStorageService {
            tx.addSyncCompletion {
                Self.storageServiceManager.recordPendingLocalAccountUpdates()
            }
        }
    }
}

// MARK: -

/// These are persisted to disk, so they must remain stable.
public enum PhoneNumberSharingMode: Int {
    case everybody = 0
    case nobody = 2
}
