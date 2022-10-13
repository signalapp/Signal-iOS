//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

private func validate(_ condition: @autoclosure () -> Bool,
                      file: String = #file,
                      function: String = #function,
                      line: Int = #line) {
#if DEBUG
    // TESTABLE_BUILD is too broad; a large test case takes 0.22s to serialize with validation and 0.13s without.
    owsAssertDebug(condition(), file: file, function: function, line: line)
#endif
}

private func prependKeyType(to data: Data) -> Data {
    validate(data.count == 32)
    return [ECPublicKey.keyTypeDJB] + data
}

private func removeKeyType(from data: Data) -> Data {
    validate((try? PublicKey(data)) != nil)
    return data.dropFirst()
}

extension LegacyChainKey {
    fileprivate func buildProto() -> SessionRecordProtos_SessionStructure.Chain.ChainKey {
        var result = SessionRecordProtos_SessionStructure.Chain.ChainKey()

        result.index = UInt32(index)
        result.key = key

        return result
    }

    fileprivate convenience init(_ proto: SessionRecordProtos_SessionStructure.Chain.ChainKey) {
        validate(proto.unknownFields.data.isEmpty)

        self.init(data: proto.key, index: Int32(proto.index))
    }
}

extension LegacyMessageKeys {
    fileprivate func buildProto() -> SessionRecordProtos_SessionStructure.Chain.MessageKey {
        validate(cipherKey.count == 32)
        validate(macKey.count == 32)
        validate(iv.count == 16)

        var result = SessionRecordProtos_SessionStructure.Chain.MessageKey()

        result.index = UInt32(index)
        result.cipherKey = cipherKey
        result.macKey = macKey
        result.iv = iv

        return result
    }

    fileprivate convenience init(_ proto: SessionRecordProtos_SessionStructure.Chain.MessageKey) {
        validate(proto.unknownFields.data.isEmpty)
        validate(proto.cipherKey.count == 32)
        validate(proto.macKey.count == 32)
        validate(proto.iv.count == 16)

        self.init(cipherKey: proto.cipherKey, macKey: proto.macKey, iv: proto.iv, index: Int32(proto.index))
    }
}

extension LegacyReceivingChain {
    fileprivate func buildProto() -> SessionRecordProtos_SessionStructure.Chain {
        validate(senderRatchetKey.count == 32)

        var result = SessionRecordProtos_SessionStructure.Chain()

        result.senderRatchetKey = prependKeyType(to: senderRatchetKey)
        result.chainKey = chainKey.buildProto()
        for messageKeys in messageKeysList {
            let messageKeys = messageKeys as! LegacyMessageKeys
            result.messageKeys.append(messageKeys.buildProto())
        }

        return result
    }

    fileprivate convenience init(_ proto: SessionRecordProtos_SessionStructure.Chain) {
        validate(proto.unknownFields.data.isEmpty)

        self.init(chainKey: LegacyChainKey(proto.chainKey), senderRatchetKey: removeKeyType(from: proto.senderRatchetKey))
        for messageKeysProto in proto.messageKeys {
            messageKeysList.add(LegacyMessageKeys(messageKeysProto))
        }
    }
}

extension LegacyPendingPreKey {
    fileprivate func buildProto() -> SessionRecordProtos_SessionStructure.PendingPreKey {
        var result = SessionRecordProtos_SessionStructure.PendingPreKey()

        // AxolotlKit uses -1 to represent "no pre-key ID".
        if preKeyId >= 0 {
            result.preKeyID = UInt32(preKeyId)
        }
        result.signedPreKeyID = signedPreKeyId
        result.baseKey = prependKeyType(to: baseKey)

        return result
    }
}

extension LegacySessionState {
    private func buildSenderChain() -> SessionRecordProtos_SessionStructure.Chain? {
        guard let ratchetKeyPair = senderRatchetKeyPair() else {
            return nil
        }

        var result = SessionRecordProtos_SessionStructure.Chain()

        result.senderRatchetKey = Data(ratchetKeyPair.identityKeyPair.publicKey.serialize())
        result.senderRatchetKeyPrivate = Data(ratchetKeyPair.identityKeyPair.privateKey.serialize())
        result.chainKey = senderChainKey().buildProto()

        return result
    }

    fileprivate func buildProto() -> SessionRecordProtos_SessionStructure? {
        guard let rootKey = self.rootKey else { return nil }

        var result = SessionRecordProtos_SessionStructure()

        result.sessionVersion = UInt32(version)

        if let localIdentityKey = self.localIdentityKey {
            result.localIdentityPublic = prependKeyType(to: localIdentityKey)
        }
        if let remoteIdentityKey = self.remoteIdentityKey {
            result.remoteIdentityPublic = prependKeyType(to: remoteIdentityKey)
        }
        result.rootKey = rootKey.keyData
        result.previousCounter = UInt32(previousCounter)
        if let chain = buildSenderChain() {
            result.senderChain = chain
        }
        for receivingChain in receivingChains {
            result.receiverChains.append(receivingChain.buildProto())
        }
        if let pendingPreKey = unacknowledgedPreKeyMessageItems() {
            result.pendingPreKey = pendingPreKey.buildProto()
        }
        result.remoteRegistrationID = UInt32(bitPattern: remoteRegistrationId)
        result.localRegistrationID = UInt32(bitPattern: localRegistrationId)
        if let aliceBaseKey = self.aliceBaseKey {
            result.aliceBaseKey = prependKeyType(to: aliceBaseKey)
        }

        return result
    }

    fileprivate convenience init(_ proto: SessionRecordProtos_SessionStructure) {
        validate(proto.unknownFields.data.isEmpty)

        self.init()
        version = Int32(proto.sessionVersion)
        localIdentityKey = removeKeyType(from: proto.localIdentityPublic)
        remoteIdentityKey = removeKeyType(from: proto.remoteIdentityPublic)
        rootKey = LegacyRootKey(data: proto.rootKey)
        previousCounter = Int32(proto.previousCounter)
        if proto.hasSenderChain {
            validate(proto.senderChain.unknownFields.data.isEmpty)

            let senderRatchetKey = try? PublicKey(proto.senderChain.senderRatchetKey)
            validate(senderRatchetKey != nil)
            let senderRatchetKeyPrivate = try? PrivateKey(proto.senderChain.senderRatchetKeyPrivate)
            validate(senderRatchetKeyPrivate != nil)
            let senderRatchetKeyPair = ECKeyPair(IdentityKeyPair(publicKey: senderRatchetKey!,
                                                                 privateKey: senderRatchetKeyPrivate!))
            setSenderChain(senderRatchetKeyPair,
                           chainKey: LegacyChainKey(proto.senderChain.chainKey))
        }
        receivingChains = proto.receiverChains.map { LegacyReceivingChain($0) }
        if proto.hasPendingPreKey {
            validate(proto.pendingPreKey.unknownFields.data.isEmpty)

            // AxolotlKit uses -1 to represent "no pre-key ID".
            let preKeyID = proto.pendingPreKey.hasPreKeyID ? Int32(proto.pendingPreKey.preKeyID) : -1
            setUnacknowledgedPreKeyMessage(preKeyID,
                                           signedPreKey: Int32(proto.pendingPreKey.signedPreKeyID),
                                           baseKey: removeKeyType(from: proto.pendingPreKey.baseKey))
        }
        remoteRegistrationId = Int32(bitPattern: proto.remoteRegistrationID)
        localRegistrationId = Int32(bitPattern: proto.localRegistrationID)
        if proto.hasAliceBaseKey {
            aliceBaseKey = removeKeyType(from: proto.aliceBaseKey)
        }
    }
}

extension LegacySessionRecord {
    fileprivate func buildProto() -> SessionRecordProtos_RecordStructure {
        var result = SessionRecordProtos_RecordStructure()

        if let currentSessionProto = sessionState().buildProto() {
            result.currentSession = currentSessionProto
        } else {
            let noPreviousSessions = previousSessionStates()?.isEmpty ?? true
            owsAssertDebug(!noPreviousSessions, "should not try to archive uninitialized sessions")
        }

        for previousSession in previousSessionStates() {
            if let sessionProto = previousSession.buildProto() {
                result.previousSessions.append(sessionProto)
            }
        }

        return result
    }

    public func serializeProto() throws -> Data {
        return try buildProto().serializedData()
    }

    public convenience init(serializedProto: Data) throws {
        let deserialized = try SessionRecordProtos_RecordStructure(serializedData: serializedProto)
        validate(deserialized.unknownFields.data.isEmpty)

        self.init()
        for stateProto in deserialized.previousSessions.reversed() {
            self.setState(LegacySessionState(stateProto))
            self.archiveCurrentState()
        }
        if deserialized.hasCurrentSession {
            self.setState(LegacySessionState(deserialized.currentSession))
        }
    }
}
