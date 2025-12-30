//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol PreKeyUploadBundle {
    var identity: OWSIdentity { get }
    func getSignedPreKey() -> LibSignalClient.SignedPreKeyRecord?
    func getPreKeyRecords() -> [LibSignalClient.PreKeyRecord]?
    func getLastResortPreKey() -> LibSignalClient.KyberPreKeyRecord?
    func getPqPreKeyRecords() -> [LibSignalClient.KyberPreKeyRecord]?
}

extension PreKeyUploadBundle {
    func isEmpty() -> Bool {
        if
            getPreKeyRecords() == nil,
            getSignedPreKey() == nil,
            getLastResortPreKey() == nil,
            getPqPreKeyRecords() == nil
        {
            return true
        }
        return false
    }
}

public final class PartialPreKeyUploadBundle: PreKeyUploadBundle {
    public let identity: OWSIdentity
    public let signedPreKey: LibSignalClient.SignedPreKeyRecord?
    public let preKeyRecords: [LibSignalClient.PreKeyRecord]?
    public let lastResortPreKey: LibSignalClient.KyberPreKeyRecord?
    public let pqPreKeyRecords: [LibSignalClient.KyberPreKeyRecord]?

    init(
        identity: OWSIdentity,
        signedPreKey: LibSignalClient.SignedPreKeyRecord? = nil,
        preKeyRecords: [LibSignalClient.PreKeyRecord]? = nil,
        lastResortPreKey: LibSignalClient.KyberPreKeyRecord? = nil,
        pqPreKeyRecords: [LibSignalClient.KyberPreKeyRecord]? = nil,
    ) {
        self.identity = identity
        self.signedPreKey = signedPreKey
        self.preKeyRecords = preKeyRecords
        self.lastResortPreKey = lastResortPreKey
        self.pqPreKeyRecords = pqPreKeyRecords
    }

    public func getSignedPreKey() -> LibSignalClient.SignedPreKeyRecord? { signedPreKey }
    public func getPreKeyRecords() -> [LibSignalClient.PreKeyRecord]? { preKeyRecords }
    public func getLastResortPreKey() -> LibSignalClient.KyberPreKeyRecord? { lastResortPreKey }
    public func getPqPreKeyRecords() -> [LibSignalClient.KyberPreKeyRecord]? { pqPreKeyRecords }
}

public final class RegistrationPreKeyUploadBundle: PreKeyUploadBundle {
    public let identity: OWSIdentity
    public let identityKeyPair: ECKeyPair
    public let signedPreKey: LibSignalClient.SignedPreKeyRecord
    public let lastResortPreKey: LibSignalClient.KyberPreKeyRecord

    public init(
        identity: OWSIdentity,
        identityKeyPair: ECKeyPair,
        signedPreKey: LibSignalClient.SignedPreKeyRecord,
        lastResortPreKey: LibSignalClient.KyberPreKeyRecord,
    ) {
        self.identity = identity
        self.identityKeyPair = identityKeyPair
        self.signedPreKey = signedPreKey
        self.lastResortPreKey = lastResortPreKey
    }

    public func getSignedPreKey() -> LibSignalClient.SignedPreKeyRecord? { signedPreKey }
    public func getPreKeyRecords() -> [LibSignalClient.PreKeyRecord]? { nil }
    public func getLastResortPreKey() -> LibSignalClient.KyberPreKeyRecord? { lastResortPreKey }
    public func getPqPreKeyRecords() -> [LibSignalClient.KyberPreKeyRecord]? { nil }
}

public struct RegistrationPreKeyUploadBundles {
    public let aci: RegistrationPreKeyUploadBundle
    public let pni: RegistrationPreKeyUploadBundle

    public init(aci: RegistrationPreKeyUploadBundle, pni: RegistrationPreKeyUploadBundle) {
        self.aci = aci
        self.pni = pni
    }
}
