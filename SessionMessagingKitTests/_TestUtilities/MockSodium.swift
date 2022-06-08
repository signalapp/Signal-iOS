// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import PromiseKit
import Sodium

@testable import SessionMessagingKit

class MockSodium: Mock<SodiumType>, SodiumType {
    func getBox() -> BoxType { return accept() as! BoxType }
    func getGenericHash() -> GenericHashType { return accept() as! GenericHashType }
    func getSign() -> SignType { return accept() as! SignType }
    func getAeadXChaCha20Poly1305Ietf() -> AeadXChaCha20Poly1305IetfType { return accept() as! AeadXChaCha20Poly1305IetfType }
    
    func generateBlindingFactor(serverPublicKey: String, genericHash: GenericHashType) -> Bytes? {
        return accept(args: [serverPublicKey, genericHash]) as? Bytes
    }
    
    func blindedKeyPair(serverPublicKey: String, edKeyPair: Box.KeyPair, genericHash: GenericHashType) -> Box.KeyPair? {
        return accept(args: [serverPublicKey, edKeyPair, genericHash]) as? Box.KeyPair
    }
    
    func sogsSignature(message: Bytes, secretKey: Bytes, blindedSecretKey ka: Bytes, blindedPublicKey kA: Bytes) -> Bytes? {
        return accept(args: [message, secretKey, ka, kA]) as? Bytes
    }
    
    func combineKeys(lhsKeyBytes: Bytes, rhsKeyBytes: Bytes) -> Bytes? {
        return accept(args: [lhsKeyBytes, rhsKeyBytes]) as? Bytes
    }
    
    func sharedBlindedEncryptionKey(secretKey a: Bytes, otherBlindedPublicKey: Bytes, fromBlindedPublicKey kA: Bytes, toBlindedPublicKey kB: Bytes, genericHash: GenericHashType) -> Bytes? {
        return accept(args: [a, otherBlindedPublicKey, kA, kB, genericHash]) as? Bytes
    }
    
    func sessionId(_ sessionId: String, matchesBlindedId blindedSessionId: String, serverPublicKey: String, genericHash: GenericHashType) -> Bool {
        return accept(args: [sessionId, blindedSessionId, serverPublicKey, genericHash]) as! Bool
    }
}
