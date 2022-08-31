// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    public struct ReactionAddResponse: Codable, Equatable {
        enum CodingKeys: String, CodingKey {
            case added
            case seqNo = "seqno"
        }
        
        /// This field indicates whether the reaction was added (true) or already present (false).
        public let added: Bool
        
        /// The seqNo after the reaction is added.
        public let seqNo: Int64?
    }
    
    public struct ReactionRemoveResponse: Codable, Equatable {
        enum CodingKeys: String, CodingKey {
            case removed
            case seqNo = "seqno"
        }
        
        /// This field indicates whether the reaction was removed (true) or was not present to begin with (false).
        public let removed: Bool
        
        /// The seqNo after the reaction is removed.
        public let seqNo: Int64?
    }
    
    public struct ReactionRemoveAllResponse: Codable, Equatable {
        enum CodingKeys: String, CodingKey {
            case removed
            case seqNo = "seqno"
        }
        
        /// This field shows the total number of reactions that were deleted.
        public let removed: Int64
        
        /// The seqNo after the reactions is all removed.
        public let seqNo: Int64?
    }
}
