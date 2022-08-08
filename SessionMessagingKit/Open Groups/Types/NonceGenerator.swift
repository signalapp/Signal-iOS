// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Sodium

public protocol NonceGenerator16ByteType {
    var NonceBytes: Int { get }
    
    func nonce() -> Array<UInt8>
}

public protocol NonceGenerator24ByteType {
    var NonceBytes: Int { get }
    
    func nonce() -> Array<UInt8>
}

extension OpenGroupAPI {
    public class NonceGenerator16Byte: NonceGenerator, NonceGenerator16ByteType {
        public var NonceBytes: Int { 16 }
    }
    
    public class NonceGenerator24Byte: NonceGenerator, NonceGenerator24ByteType {
        public var NonceBytes: Int { 24 }
    }
}
