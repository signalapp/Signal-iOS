// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium
import SessionSnodeKit

// MARK: - Dependencies

extension OpenGroupAPI {
    public class Dependencies {
        private var _api: OnionRequestAPIType.Type?
        public var api: OnionRequestAPIType.Type {
            get { getValueSettingIfNull(&_api) { OnionRequestAPI.self } }
            set { _api = newValue }
        }
        
        private var _storage: SessionMessagingKitStorageProtocol?
        public var storage: SessionMessagingKitStorageProtocol {
            get { getValueSettingIfNull(&_storage) { SNMessagingKitConfiguration.shared.storage } }
            set { _storage = newValue }
        }
        
        private var _sodium: SodiumType?
        public var sodium: SodiumType {
            get { getValueSettingIfNull(&_sodium) { Sodium() } }
            set { _sodium = newValue }
        }
        
        private var _aeadXChaCha20Poly1305Ietf: AeadXChaCha20Poly1305IetfType?
        public var aeadXChaCha20Poly1305Ietf: AeadXChaCha20Poly1305IetfType {
            get { getValueSettingIfNull(&_aeadXChaCha20Poly1305Ietf) { sodium.getAeadXChaCha20Poly1305Ietf() } }
            set { _aeadXChaCha20Poly1305Ietf = newValue }
        }
        
        private var _sign: SignType?
        public var sign: SignType {
            get { getValueSettingIfNull(&_sign) { sodium.getSign() } }
            set { _sign = newValue }
        }
        
        private var _genericHash: GenericHashType?
        public var genericHash: GenericHashType {
            get { getValueSettingIfNull(&_genericHash) { sodium.getGenericHash() } }
            set { _genericHash = newValue }
        }
        
        private var _ed25519: Ed25519Type.Type?
        public var ed25519: Ed25519Type.Type {
            get { getValueSettingIfNull(&_ed25519) { Ed25519.self } }
            set { _ed25519 = newValue }
        }
        
        private var _nonceGenerator16: NonceGenerator16ByteType?
        public var nonceGenerator16: NonceGenerator16ByteType {
            get { getValueSettingIfNull(&_nonceGenerator16) { NonceGenerator16Byte() } }
            set { _nonceGenerator16 = newValue }
        }
        
        private var _nonceGenerator24: NonceGenerator24ByteType?
        public var nonceGenerator24: NonceGenerator24ByteType {
            get { getValueSettingIfNull(&_nonceGenerator24) { NonceGenerator24Byte() } }
            set { _nonceGenerator24 = newValue }
        }
        
        private var _date: Date?
        public var date: Date {
            get { getValueSettingIfNull(&_date) { Date() } }
            set { _date = newValue }
        }
        
        // MARK: - Initialization
        
        public init(
            api: OnionRequestAPIType.Type? = nil,
            storage: SessionMessagingKitStorageProtocol? = nil,
            sodium: SodiumType? = nil,
            aeadXChaCha20Poly1305Ietf: AeadXChaCha20Poly1305IetfType? = nil,
            sign: SignType? = nil,
            genericHash: GenericHashType? = nil,
            ed25519: Ed25519Type.Type? = nil,
            nonceGenerator16: NonceGenerator16ByteType? = nil,
            nonceGenerator24: NonceGenerator24ByteType? = nil,
            date: Date? = nil
        ) {
            _api = api
            _storage = storage
            _sodium = sodium
            _aeadXChaCha20Poly1305Ietf = aeadXChaCha20Poly1305Ietf
            _sign = sign
            _genericHash = genericHash
            _ed25519 = ed25519
            _nonceGenerator16 = nonceGenerator16
            _nonceGenerator24 = nonceGenerator24
            _date = date
        }
        
        // MARK: - Convenience
        
        public func with(
            api: OnionRequestAPIType.Type? = nil,
            storage: SessionMessagingKitStorageProtocol? = nil,
            sodium: SodiumType? = nil,
            aeadXChaCha20Poly1305Ietf: AeadXChaCha20Poly1305IetfType? = nil,
            sign: SignType? = nil,
            genericHash: GenericHashType? = nil,
            ed25519: Ed25519Type.Type? = nil,
            nonceGenerator16: NonceGenerator16ByteType? = nil,
            nonceGenerator24: NonceGenerator24ByteType? = nil,
            date: Date? = nil
        ) -> Dependencies {
            return Dependencies(
                api: (api ?? self._api),
                storage: (storage ?? self._storage),
                sodium: (sodium ?? self._sodium),
                aeadXChaCha20Poly1305Ietf: (aeadXChaCha20Poly1305Ietf ?? self._aeadXChaCha20Poly1305Ietf),
                sign: (sign ?? self._sign),
                genericHash: (genericHash ?? self._genericHash),
                ed25519: (ed25519 ?? self._ed25519),
                nonceGenerator16: (nonceGenerator16 ?? self._nonceGenerator16),
                nonceGenerator24: (nonceGenerator24 ?? self._nonceGenerator24),
                date: (date ?? self._date)
            )
        }
    }
}

// MARK: - Convenience

fileprivate func getValueSettingIfNull<T>(_ maybeValue: inout T?, _ valueGenerator: () -> T) -> T {
    guard let value: T = maybeValue else {
        let value: T = valueGenerator()
        maybeValue = value
        return value
    }
    
    return value
}
