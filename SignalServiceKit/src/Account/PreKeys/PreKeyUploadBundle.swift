//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol PreKeyUploadBundle {
    var identity: OWSIdentity { get }
    var identityKeyPair: ECKeyPair { get }
    func getSignedPreKey() -> SignedPreKeyRecord?
    func getPreKeyRecords() -> [PreKeyRecord]?
    func getLastResortPreKey() -> KyberPreKeyRecord?
    func getPqPreKeyRecords() -> [KyberPreKeyRecord]?
}

public final class PartialPreKeyUploadBundle: PreKeyUploadBundle {
    public let identity: OWSIdentity
    public let identityKeyPair: ECKeyPair
    public let signedPreKey: SignedPreKeyRecord?
    public let preKeyRecords: [PreKeyRecord]?
    public let lastResortPreKey: KyberPreKeyRecord?
    public let pqPreKeyRecords: [KyberPreKeyRecord]?

    internal init(
        identity: OWSIdentity,
        identityKeyPair: ECKeyPair,
        signedPreKey: SignedPreKeyRecord? = nil,
        preKeyRecords: [PreKeyRecord]? = nil,
        lastResortPreKey: KyberPreKeyRecord? = nil,
        pqPreKeyRecords: [KyberPreKeyRecord]? = nil
    ) {
        self.identity = identity
        self.identityKeyPair = identityKeyPair
        self.signedPreKey = signedPreKey
        self.preKeyRecords = preKeyRecords
        self.lastResortPreKey = lastResortPreKey
        self.pqPreKeyRecords = pqPreKeyRecords
    }

    public func getSignedPreKey() -> SignedPreKeyRecord? { signedPreKey }
    public func getPreKeyRecords() -> [PreKeyRecord]? { preKeyRecords }
    public func getLastResortPreKey() -> KyberPreKeyRecord? { lastResortPreKey }
    public func getPqPreKeyRecords() -> [KyberPreKeyRecord]? { pqPreKeyRecords }
}

// TODO: add prekey bundle to be used for registration
