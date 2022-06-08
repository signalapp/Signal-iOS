// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import PromiseKit
import SessionUtilitiesKit

public final class SnodeMessage: Codable {
    private enum CodingKeys: String, CodingKey {
        case recipient = "pubKey"
        case data
        case ttl
        case timestampMs = "timestamp"
        case nonce
    }
    
    /// The hex encoded public key of the recipient.
    public let recipient: String
    
    /// The content of the message.
    public let data: String
    
    /// The time to live for the message in milliseconds.
    public let ttl: UInt64
    
    /// When the proof of work was calculated.
    ///
    /// - Note: Expressed as milliseconds since 00:00:00 UTC on 1 January 1970.
    public let timestampMs: UInt64

    // MARK: - Initialization
    
    public init(recipient: String, data: String, ttl: UInt64, timestampMs: UInt64) {
        self.recipient = recipient
        self.data = data
        self.ttl = ttl
        self.timestampMs = timestampMs
    }
}

// MARK: - Codable

extension SnodeMessage {
    public convenience init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        self.init(
            recipient: try container.decode(String.self, forKey: .recipient),
            data: try container.decode(String.self, forKey: .data),
            ttl: try container.decode(UInt64.self, forKey: .ttl),
            timestampMs: try container.decode(UInt64.self, forKey: .timestampMs)
        )
    }
    
    public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(
            (Features.useTestnet ? recipient.removingIdPrefixIfNeeded() : recipient),
            forKey: .recipient
        )
        try container.encode(data, forKey: .data)
        try container.encode(ttl, forKey: .ttl)
        try container.encode(timestampMs, forKey: .timestampMs)
        try container.encode("", forKey: .nonce)
    }
}
