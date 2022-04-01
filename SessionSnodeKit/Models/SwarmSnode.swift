// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

/// It looks like the structure for the service node returned from `get_snodes_for_pubkey` is different from
/// the usual structure, this type is used as an intemediary to convert to the usual 'Snode' type
// FIXME: Hopefully at some point this different Snode structure will be deprecated and can be removed
internal struct SwarmSnode: Codable {
    public enum CodingKeys: String, CodingKey {
        case address = "ip"
        case port
        case ed25519PublicKey = "pubkey_ed25519"
        case x25519PublicKey = "pubkey_x25519"
    }
    
    let address: String
    let port: UInt16
    let ed25519PublicKey: String
    let x25519PublicKey: String
}

// MARK: - Convenience

extension SwarmSnode {
    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        do {
            let address: String = try container.decode(String.self, forKey: .address)
            let portString: String = try container.decode(String.self, forKey: .port)
            
            guard address != "0.0.0.0", let port: UInt16 = UInt16(portString) else {
                throw SnodeAPI.Error.invalidIP
            }
            
            self = SwarmSnode(
                address: (address.starts(with: "https://") ? address : "https://\(address)"),
                port: port,
                ed25519PublicKey: try container.decode(String.self, forKey: .ed25519PublicKey),
                x25519PublicKey: try container.decode(String.self, forKey: .x25519PublicKey)
            )
        }
        catch {
            SNLog("Failed to parse snode: \(error.localizedDescription).")
            throw HTTP.Error.invalidJSON
        }
    }

    func toSnode() -> Snode {
        return Snode(
            address: address,
            port: port,
            ed25519PublicKey: ed25519PublicKey,
            x25519PublicKey: x25519PublicKey
        )
    }
}
