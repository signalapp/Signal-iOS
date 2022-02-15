// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

enum Header: String {
    case authorization = "Authorization"
    case contentType = "Content-Type"
    
    case room = "Room"  // TODO: Confirm this is needed
    case fileName = "X-Filename"
    
    case sogsPubKey = "X-SOGS-Pubkey"
    case sogsNonce = "X-SOGS-Nonce"
    case sogsTimestamp = "X-SOGS-Timestamp"
    case sogsHash = "X-SOGS-Hash"
}

// MARK: - Convenience

extension Dictionary where Key == Header, Value == String {
    func toHTTPHeaders() -> [String: String] {
        return self.reduce(into: [:]) { result, next in result[next.key.rawValue] = next.value }
    }
}
