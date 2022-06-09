// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

public enum OnionRequestAPIDestination: CustomStringConvertible {
    case snode(Snode)
    case server(host: String, target: String, x25519PublicKey: String, scheme: String?, port: UInt16?)
    
    public var description: String {
        switch self {
            case .snode(let snode): return "Service node \(snode.ip):\(snode.port)"
            case .server(let host, _, _, _, _): return host
        }
    }
}
