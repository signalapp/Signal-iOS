//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
public import LibSignalClient

public struct Fingerprint {
    private let rawValue: Data

    public let identityKey: IdentityKey

    public static func derive(
        forAci aci: Aci,
        identityKey: IdentityKey,
        iterations: UInt32 = 5200,
    ) -> Self {
        let version = 0 as UInt16
        let identityKeyData = identityKey.serialize()

        var hash = Data()
        hash.append(version.bigEndianData)
        hash.append(identityKeyData)
        hash.append(aci.serviceIdBinary)

        for _ in 0..<iterations {
            hash.append(identityKeyData)
            let digestData = SHA512.hash(data: hash)
            hash.removeAll(keepingCapacity: true)
            hash.append(contentsOf: digestData)
        }

        return Self(identityKey: identityKey, rawValue: hash)
    }

    private init(identityKey: IdentityKey, rawValue: Data) {
        self.identityKey = identityKey
        self.rawValue = rawValue
    }

    func dataRepresentation() -> Data {
        return self.rawValue.prefix(32)
    }

    func stringRepresentation() -> String {
        return stride(from: 0, to: 30, by: 5).reduce(into: "") {
            $0 += Self.stringRepresentationChunk(forData: self.rawValue.dropFirst($1).prefix(5))
        }
    }

    private static func stringRepresentationChunk(forData dataChunk: Data) -> String {
        owsPrecondition(dataChunk.count == 5)
        guard let integerValue = UInt64(bigEndianData: Data(count: 3) + dataChunk) else {
            owsFail("can always parse integer from 8 bytes")
        }
        return unsafe String(format: "%05llu", integerValue % 100000)
    }
}
