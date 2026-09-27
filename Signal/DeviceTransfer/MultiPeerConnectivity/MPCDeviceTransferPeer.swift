//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import MultipeerConnectivity

struct MPCDeviceTransferPeer: DeviceTransfer.Peer {
    var displayName: String { mcPeerID.displayName }
    var id: Int { mcPeerID.hashValue }

    let mcPeerID: MCPeerID
    init(mcPeerID: MCPeerID) {
        self.mcPeerID = mcPeerID
    }

    init(displayName: String) {
        self.mcPeerID = MCPeerID(displayName: displayName)
    }

    init?(with peerIdData: Data) {
        guard let peerId = try? NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: peerIdData) else {
            return nil
        }
        self.mcPeerID = peerId
    }

    func encoded() throws -> Data {
        return try NSKeyedArchiver.archivedData(withRootObject: mcPeerID, requiringSecureCoding: true)
    }

    static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.mcPeerID == rhs.mcPeerID
    }
}
