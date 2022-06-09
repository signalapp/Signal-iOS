// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

struct SnodePoolResponse: Codable {
    struct SnodePool: Codable {
        public enum CodingKeys: String, CodingKey {
            case serviceNodeStates = "service_node_states"
        }
        
        let serviceNodeStates: [Failable<Snode>]
    }
    
    let result: SnodePool
}
