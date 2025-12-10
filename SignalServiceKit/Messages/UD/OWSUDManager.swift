//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

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

/// Represents an Unidentified Access Key that we believe may be valid.
///
/// "we believe may be valid": Our local state may be outdated, so the UAK
/// may be unauthorized when we use it. But we think it's worth trying.
///
/// If we're not sure (`.unknown`), or if we've previously confirmed it's
/// valid (`.enabled` & `.unrestricted`), we can create this type. If we've
/// previously confirmed it's not valid, we can't create this type.
public struct OWSUDAccess {
    let key: SMKUDAccessKey
    let mode: Mode

    enum Mode {
        case unknown
        case enabled
        case unrestricted
    }
}

// MARK: -

public struct SenderCertificates {
    let defaultCert: SenderCertificate
    let uuidOnlyCert: SenderCertificate
}

// MARK: -

public protocol OWSUDManager {

    var trustRoots: [PublicKey] { get }

    // MARK: - Recipient State

    func setUnidentifiedAccessMode(_ mode: UnidentifiedAccessMode, for aci: Aci, tx: DBWriteTransaction)

    func udAccessKey(for aci: Aci, tx: DBReadTransaction) -> SMKUDAccessKey?

    func udAccess(for aci: Aci, tx: DBReadTransaction) -> OWSUDAccess?

    func fetchAllAciUakPairs(tx: DBReadTransaction) -> [Aci: SMKUDAccessKey]

    // MARK: Sender Certificate

    func fetchSenderCertificates() async throws -> SenderCertificates

    func removeSenderCertificates(transaction: DBWriteTransaction)
    func removeSenderCertificates(tx: DBWriteTransaction)

    // MARK: Unrestricted Access

    func shouldAllowUnrestrictedAccessLocal() -> Bool

    func shouldAllowUnrestrictedAccessLocal(transaction: DBReadTransaction) -> Bool

    func setShouldAllowUnrestrictedAccessLocal(_ value: Bool)
    func setShouldAllowUnrestrictedAccessLocal(_ value: Bool, tx: DBWriteTransaction)

    func phoneNumberSharingMode(tx: DBReadTransaction) -> PhoneNumberSharingMode?

    func setPhoneNumberSharingMode(
        _ mode: PhoneNumberSharingMode,
        updateStorageServiceAndProfile: Bool,
        tx: DBWriteTransaction
    )
}

// MARK: -

public class OWSUDManagerImpl: OWSUDManager {

    private let keyValueStore = KeyValueStore(collection: "kUDCollection")
    private let aciAccessStore = KeyValueStore(collection: "kUnidentifiedAccessUUIDCollection")

    // MARK: Local Configuration State

    // These keys contain the word "Production" for historical reasons, but
    // they store sender certificates in both production & staging builds.
    private let kUDCurrentSenderCertificateKey = "kUDCurrentSenderCertificateKey_Production-uuid"

    private let kUDUnrestrictedAccessKey = "kUDUnrestrictedAccessKey"

    // MARK: Recipient State

    private let db: any DB
    private let tsAccountManager: any TSAccountManager

    // Exposed for testing
    public internal(set) var trustRoots: [PublicKey]

    public init(
        cron: Cron,
        db: any DB,
        tsAccountManager: any TSAccountManager,
    ) {
        self.db = db
        self.trustRoots = OWSUDManagerImpl.trustRoots()
        self.tsAccountManager = tsAccountManager

        SwiftSingletons.register(self)

        // We can fill in any missing sender certificate async; message sending
        // will fill in the sender certificate sooner if it needs it.
        cron.schedulePeriodically(
            uniqueKey: .fetchSenderCertificates,
            approximateInterval: .day,
            mustBeRegistered: true,
            mustBeConnected: true,
            operation: { _ = try await self.fetchSenderCertificates(forceRefresh: true) },
        )
    }

    // MARK: - Recipient state

    private func unidentifiedAccessMode(for aci: Aci, tx: DBReadTransaction) -> UnidentifiedAccessMode {
        let existingValue: UnidentifiedAccessMode? = {
            guard let rawValue = aciAccessStore.getInt(aci.serviceIdUppercaseString, transaction: tx) else {
                return nil
            }
            return UnidentifiedAccessMode(rawValue: rawValue)
        }()
        return existingValue ?? .unknown
    }

    public func setUnidentifiedAccessMode(
        _ mode: UnidentifiedAccessMode,
        for aci: Aci,
        tx: DBWriteTransaction
    ) {
        aciAccessStore.setInt(mode.rawValue, key: aci.serviceIdUppercaseString, transaction: tx)
    }

    public func fetchAllAciUakPairs(tx: DBReadTransaction) -> [Aci: SMKUDAccessKey] {
        let acis: [Aci] = aciAccessStore.allKeys(transaction: tx).compactMap { aciString in
            guard let aci = Aci.parseFrom(aciString: aciString) else {
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
    public func udAccessKey(for aci: Aci, tx: DBReadTransaction) -> SMKUDAccessKey? {
        let profileManager = SSKEnvironment.shared.profileManagerRef
        guard let profileKey = profileManager.userProfile(for: SignalServiceAddress(aci), tx: tx)?.profileKey else {
            return nil
        }
        return SMKUDAccessKey(profileKey: profileKey)
    }

    // Returns the UD access key for sending to a given recipient or fetching a profile
    public func udAccess(for aci: Aci, tx: DBReadTransaction) -> OWSUDAccess? {
        let accessKey: SMKUDAccessKey
        let accessMode: OWSUDAccess.Mode

        switch unidentifiedAccessMode(for: aci, tx: tx) {
        case .unrestricted:
            accessKey = .zeroedKey
            accessMode = .unrestricted
        case .unknown:
            // If we're not sure, try our best to use the right key.
            accessKey = udAccessKey(for: aci, tx: tx) ?? .zeroedKey
            accessMode = .unknown
        case .enabled:
            guard let knownAccessKey = udAccessKey(for: aci, tx: tx) else {
                // Shouldn't happen because we need a profile key to enable it.
                Logger.warn("Missing profile key for UD-enabled user: \(aci)")
                return nil
            }
            accessKey = knownAccessKey
            accessMode = .enabled
        case .disabled:
            return nil
        }
        return OWSUDAccess(key: accessKey, mode: accessMode)
    }

    // MARK: - Sender Certificate

    private func loadSenderCertificate(aciOnly: Bool) -> SenderCertificate? {
        let dataValue = self.db.read { tx in
            return self.keyValueStore.getData(self.senderCertificateKey(aciOnly: aciOnly), transaction: tx)
        }

        guard let dataValue else {
            return nil
        }

        do {
            let senderCertificate = try SenderCertificate(dataValue)
            try validateCertificate(senderCertificate)
            return senderCertificate
        } catch {
            Logger.warn("Ignoring invalid cached sender certificate: \(error)")
            return nil
        }
    }

    func setSenderCertificate(aciOnly: Bool, certificateData: Data) async {
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            self.keyValueStore.setData(certificateData, key: self.senderCertificateKey(aciOnly: aciOnly), transaction: tx)
        }
    }

    public func removeSenderCertificates(transaction: DBWriteTransaction) {
        keyValueStore.removeValue(forKey: senderCertificateKey(aciOnly: true), transaction: transaction)
        keyValueStore.removeValue(forKey: senderCertificateKey(aciOnly: false), transaction: transaction)
    }

    public func removeSenderCertificates(tx: DBWriteTransaction) {
        removeSenderCertificates(transaction: tx)
    }

    private func senderCertificateKey(aciOnly: Bool) -> String {
        let baseKey = kUDCurrentSenderCertificateKey
        if aciOnly {
            return "\(baseKey)-withoutPhoneNumber"
        } else {
            return baseKey
        }
    }

    private let fetchQueue = ConcurrentTaskQueue(concurrentLimit: 1)

    public func fetchSenderCertificates() async throws -> SenderCertificates {
        try await fetchSenderCertificates(forceRefresh: false)
    }

    private func fetchSenderCertificates(forceRefresh: Bool) async throws -> SenderCertificates {
        return try await fetchQueue.run {
            return try await _fetchSenderCertificates(forceRefresh: forceRefresh)
        }
    }

    private func _fetchSenderCertificates(forceRefresh: Bool) async throws -> SenderCertificates {
        _ = try self.tsAccountManager.registeredStateWithMaybeSneakyTransaction()
        async let defaultCert = fetchSenderCertificate(aciOnly: false, forceRefresh: forceRefresh)
        async let aciOnlyCert = fetchSenderCertificate(aciOnly: true, forceRefresh: forceRefresh)
        return SenderCertificates(
            defaultCert: try await defaultCert,
            uuidOnlyCert: try await aciOnlyCert
        )
    }

    private func fetchSenderCertificate(aciOnly: Bool, forceRefresh: Bool) async throws -> SenderCertificate {
        if !forceRefresh {
            // If there is a valid cached sender certificate, use that.
            if let certificate = loadSenderCertificate(aciOnly: aciOnly) {
                return certificate
            }
        }

        let senderCertificate: SenderCertificate
        do {
            senderCertificate = try await self.requestSenderCertificate(aciOnly: aciOnly)
        } catch where error.isNetworkFailureOrTimeout || error.is5xxServiceResponse || error is CancellationError {
            throw error
        } catch {
            Logger.warn("Couldn't fetch Sealed Sender certificate: \(error)")
            SSKEnvironment.shared.notificationPresenterRef.notifyTestPopulation(ofErrorMessage: "Couldn't parse Sealed Sender certificate")
            throw error
        }
        await self.setSenderCertificate(aciOnly: aciOnly, certificateData: senderCertificate.serialize())
        return senderCertificate
    }

    private func requestSenderCertificate(aciOnly: Bool) async throws -> SenderCertificate {
        let certificateRequest = OWSRequestFactory.udSenderCertificateRequest(uuidOnly: aciOnly)
        let certificateResponse = try await SSKEnvironment.shared.networkManagerRef
            .asyncRequest(certificateRequest)

        let certificateData: Data = try {
            guard let parser = certificateResponse.responseBodyParamParser else {
                throw OWSUDError.invalidData(description: "Missing or invalid JSON")
            }

            return try parser.requiredBase64EncodedData(key: "certificate")
        }()

        let senderCertificate = try SenderCertificate(certificateData)
        try validateCertificate(senderCertificate)
        return senderCertificate
    }

    private func validateCertificate(_ certificate: SenderCertificate) throws {
        guard
            let deviceId = DeviceId(validating: certificate.deviceId),
            self.tsAccountManager.storedDeviceIdWithMaybeTransaction.equals(deviceId)
        else {
            throw OWSUDError.invalidData(description: "Sender certificate has incorrect device ID")
        }

        let localIdentifiers = self.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction

        let sender = certificate.sender
        guard sender.e164 == nil || sender.e164 == localIdentifiers?.phoneNumber else {
            throw OWSUDError.invalidData(description: "Sender certificate has incorrect phone number")
        }

        guard sender.senderAci == localIdentifiers!.aci else {
            throw OWSUDError.invalidData(description: "Sender certificate has incorrect ACI")
        }

        // Ensure that the certificate will not expire in the next hour.
        // We want a threshold long enough to ensure that any outgoing message
        // sends will complete before the expiration.
        let nowMs = NSDate.ows_millisecondTimeStamp()
        let anHourFromNowMs = nowMs + UInt64.hourInMs

        guard certificate.validate(trustRoots: trustRoots, time: anHourFromNowMs) else {
            throw OWSUDError.invalidData(description: "Sender certificate failed validation")
        }
    }

    public class func trustRoots() -> [PublicKey] {
        var trustRoots = [PublicKey]()
        for trustRoot in TSConstants.kUDTrustRoots {
            do {
                guard let data = Data(base64Encoded: trustRoot) else {
                    // This exits.
                    owsFail("Invalid trust root data.")
                }
                trustRoots.append(try PublicKey(data))
            } catch {
                // This exits.
                owsFail("Invalid trust root.")
            }
        }
        return trustRoots
    }

    // MARK: - Unrestricted Access

    public func shouldAllowUnrestrictedAccessLocal() -> Bool {
        return self.db.read { transaction in
            return self.shouldAllowUnrestrictedAccessLocal(transaction: transaction)
        }
    }

    public func shouldAllowUnrestrictedAccessLocal(transaction: DBReadTransaction) -> Bool {
        return self.keyValueStore.getBool(self.kUDUnrestrictedAccessKey, defaultValue: false, transaction: transaction)
    }

    public func setShouldAllowUnrestrictedAccessLocal(_ value: Bool) {
        self.db.write { transaction in
            setShouldAllowUnrestrictedAccessLocal(value, tx: transaction)
        }
    }

    public func setShouldAllowUnrestrictedAccessLocal(_ value: Bool, tx: DBWriteTransaction) {
        self.keyValueStore.setBool(value, key: self.kUDUnrestrictedAccessKey, transaction: tx)

        // Try to update the account attributes to reflect this change.
        tx.addSyncCompletion {
            Task {
                do {
                    try await DependenciesBridge.shared.accountAttributesUpdater.updateAccountAttributes(authedAccount: .implicit())
                } catch {
                    Logger.warn("Error: \(error)")
                }
            }
        }
    }

    // MARK: - Phone Number Sharing

    private static var phoneNumberSharingModeKey: String { "phoneNumberSharingMode" }

    public func phoneNumberSharingMode(tx: DBReadTransaction) -> PhoneNumberSharingMode? {
        guard let rawMode = keyValueStore.getInt(Self.phoneNumberSharingModeKey, transaction: tx) else {
            return nil
        }
        return PhoneNumberSharingMode(rawValue: rawMode)
    }

    public func setPhoneNumberSharingMode(
        _ mode: PhoneNumberSharingMode,
        updateStorageServiceAndProfile: Bool,
        tx: DBWriteTransaction
    ) {
        keyValueStore.setInt(mode.rawValue, key: Self.phoneNumberSharingModeKey, transaction: tx)

        if updateStorageServiceAndProfile {
            tx.addSyncCompletion {
                SSKEnvironment.shared.storageServiceManagerRef.recordPendingLocalAccountUpdates()
            }
            _ = SSKEnvironment.shared.profileManagerRef.reuploadLocalProfile(
                unsavedRotatedProfileKey: nil,
                mustReuploadAvatar: false,
                authedAccount: .implicit(),
                tx: tx
            )
        }
    }
}

// MARK: -

/// These are persisted to disk, so they must remain stable.
public enum PhoneNumberSharingMode: Int {
    case everybody = 0
    case nobody = 2

    public static let defaultValue: PhoneNumberSharingMode = .nobody
}

extension Optional where Wrapped == PhoneNumberSharingMode {
    public var orDefault: PhoneNumberSharingMode {
        return self ?? .defaultValue
    }
}

public class OWSMockUDManager: OWSUDManager {

    public var trustRoots: [LibSignalClient.PublicKey] = []

    public func setUnidentifiedAccessMode(_ mode: UnidentifiedAccessMode, for aci: LibSignalClient.Aci, tx: DBWriteTransaction) {
    }

    public func udAccessKey(for aci: LibSignalClient.Aci, tx: DBReadTransaction) -> SMKUDAccessKey? {
        return nil
    }

    public func udAccess(for aci: LibSignalClient.Aci, tx: DBReadTransaction) -> OWSUDAccess? {
        return nil
    }

    public func fetchAllAciUakPairs(tx: DBReadTransaction) -> [LibSignalClient.Aci: SMKUDAccessKey] {
        return [:]
    }

    public func fetchSenderCertificates() async throws -> SenderCertificates {
        fatalError("not implemented")
    }

    public func removeSenderCertificates(transaction: DBWriteTransaction) {
    }

    public func removeSenderCertificates(tx: DBWriteTransaction) {
    }

    public func shouldAllowUnrestrictedAccessLocal() -> Bool {
        return true
    }

    public func shouldAllowUnrestrictedAccessLocal(transaction: DBReadTransaction) -> Bool {
        return true
    }

    public func setShouldAllowUnrestrictedAccessLocal(_ value: Bool) {
    }

    public func setShouldAllowUnrestrictedAccessLocal(_ value: Bool, tx: DBWriteTransaction) {
    }

    public func phoneNumberSharingMode(tx: DBReadTransaction) -> PhoneNumberSharingMode? {
        return nil
    }

    public func setPhoneNumberSharingMode(_ mode: PhoneNumberSharingMode, updateStorageServiceAndProfile: Bool, tx: DBWriteTransaction) {
    }
}
