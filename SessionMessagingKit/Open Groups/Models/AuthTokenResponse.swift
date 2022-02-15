// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    struct AuthTokenResponse: Codable {
         struct Challenge: Codable {
             enum CodingKeys: String, CodingKey {
                 case ciphertext = "ciphertext"
                 case ephemeralPublicKey = "ephemeral_public_key"
             }
             
             let ciphertext: Data
             let ephemeralPublicKey: Data
         }

        let challenge: Challenge
    }
}

// MARK: - Codable

extension OpenGroupAPI.AuthTokenResponse.Challenge {
    init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        let base64EncodedCiphertext: String = try container.decode(String.self, forKey: .ciphertext)
        let base64EncodedEphemeralPublicKey: String = try container.decode(String.self, forKey: .ephemeralPublicKey)
        
        guard let ciphertext = Data(base64Encoded: base64EncodedCiphertext), let ephemeralPublicKey = Data(base64Encoded: base64EncodedEphemeralPublicKey) else {
            throw OpenGroupAPI.Error.parsingFailed
        }
        
        self = OpenGroupAPI.AuthTokenResponse.Challenge(
            ciphertext: ciphertext,
            ephemeralPublicKey: ephemeralPublicKey
        )
    }
    
    public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(ciphertext.base64EncodedString(), forKey: .ciphertext)
        try container.encode(ephemeralPublicKey.base64EncodedString(), forKey: .ephemeralPublicKey)
    }
}
