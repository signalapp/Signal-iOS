// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Sodium

extension OpenGroupAPIV2 {
    class NonceGenerator16Byte: NonceGenerator {
        var NonceBytes: Int { 16 }
    }
}
