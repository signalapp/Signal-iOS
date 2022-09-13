// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import Sodium
import SessionSnodeKit
import SessionUtilitiesKit

public class SMKDependencies: Dependencies {
    internal var _onionApi: Atomic<OnionRequestAPIType.Type?>
    public var onionApi: OnionRequestAPIType.Type {
        get { Dependencies.getValueSettingIfNull(&_onionApi) { OnionRequestAPI.self } }
        set { _onionApi.mutate { $0 = newValue } }
    }
    
    internal var _sodium: Atomic<SodiumType?>
    public var sodium: SodiumType {
        get { Dependencies.getValueSettingIfNull(&_sodium) { Sodium() } }
        set { _sodium.mutate { $0 = newValue } }
    }
    
    internal var _box: Atomic<BoxType?>
    public var box: BoxType {
        get { Dependencies.getValueSettingIfNull(&_box) { sodium.getBox() } }
        set { _box.mutate { $0 = newValue } }
    }
    
    internal var _genericHash: Atomic<GenericHashType?>
    public var genericHash: GenericHashType {
        get { Dependencies.getValueSettingIfNull(&_genericHash) { sodium.getGenericHash() } }
        set { _genericHash.mutate { $0 = newValue } }
    }
    
    internal var _sign: Atomic<SignType?>
    public var sign: SignType {
        get { Dependencies.getValueSettingIfNull(&_sign) { sodium.getSign() } }
        set { _sign.mutate { $0 = newValue } }
    }
    
    internal var _aeadXChaCha20Poly1305Ietf: Atomic<AeadXChaCha20Poly1305IetfType?>
    public var aeadXChaCha20Poly1305Ietf: AeadXChaCha20Poly1305IetfType {
        get { Dependencies.getValueSettingIfNull(&_aeadXChaCha20Poly1305Ietf) { sodium.getAeadXChaCha20Poly1305Ietf() } }
        set { _aeadXChaCha20Poly1305Ietf.mutate { $0 = newValue } }
    }
    
    internal var _ed25519: Atomic<Ed25519Type?>
    public var ed25519: Ed25519Type {
        get { Dependencies.getValueSettingIfNull(&_ed25519) { Ed25519Wrapper() } }
        set { _ed25519.mutate { $0 = newValue } }
    }
    
    internal var _nonceGenerator16: Atomic<NonceGenerator16ByteType?>
    public var nonceGenerator16: NonceGenerator16ByteType {
        get { Dependencies.getValueSettingIfNull(&_nonceGenerator16) { OpenGroupAPI.NonceGenerator16Byte() } }
        set { _nonceGenerator16.mutate { $0 = newValue } }
    }
    
    internal var _nonceGenerator24: Atomic<NonceGenerator24ByteType?>
    public var nonceGenerator24: NonceGenerator24ByteType {
        get { Dependencies.getValueSettingIfNull(&_nonceGenerator24) { OpenGroupAPI.NonceGenerator24Byte() } }
        set { _nonceGenerator24.mutate { $0 = newValue } }
    }
    
    // MARK: - Initialization
    
    public init(
        onionApi: OnionRequestAPIType.Type? = nil,
        generalCache: Atomic<GeneralCacheType>? = nil,
        storage: Storage? = nil,
        sodium: SodiumType? = nil,
        box: BoxType? = nil,
        genericHash: GenericHashType? = nil,
        sign: SignType? = nil,
        aeadXChaCha20Poly1305Ietf: AeadXChaCha20Poly1305IetfType? = nil,
        ed25519: Ed25519Type? = nil,
        nonceGenerator16: NonceGenerator16ByteType? = nil,
        nonceGenerator24: NonceGenerator24ByteType? = nil,
        standardUserDefaults: UserDefaultsType? = nil,
        date: Date? = nil
    ) {
        _onionApi = Atomic(onionApi)
        _sodium = Atomic(sodium)
        _box = Atomic(box)
        _genericHash = Atomic(genericHash)
        _sign = Atomic(sign)
        _aeadXChaCha20Poly1305Ietf = Atomic(aeadXChaCha20Poly1305Ietf)
        _ed25519 = Atomic(ed25519)
        _nonceGenerator16 = Atomic(nonceGenerator16)
        _nonceGenerator24 = Atomic(nonceGenerator24)
        
        super.init(
            generalCache: generalCache,
            storage: storage,
            standardUserDefaults: standardUserDefaults,
            date: date
        )
    }
}
