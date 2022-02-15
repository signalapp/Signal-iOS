// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Sodium

public protocol NonceGenerator16ByteType {
    func nonce() -> Array<UInt8>
}

extension NonceGenerator16ByteType {
    
}

extension OpenGroupAPIV2 {
    public class NonceGenerator16Byte: NonceGenerator, NonceGenerator16ByteType {
        public var NonceBytes: Int { 16 }
        
        public init() {}
    }
}
