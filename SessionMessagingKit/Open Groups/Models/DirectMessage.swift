// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    public struct DirectMessage: Codable {
        enum CodingKeys: String, CodingKey {
            case id
            case sender
            case recipient
            case posted = "posted_at"
            case expires = "expires_at"
            case base64EncodedMessage = "message"
        }
        
        /// The unique integer message id
        public let id: Int64
        
        /// The (blinded) Session ID of the sender of the message
        public let sender: String
        
        /// The (blinded) Session ID of the recipient of the message
        public let recipient: String
        
        /// Unix timestamp when the message was received by SOGS
        public let posted: TimeInterval
        
        /// Unix timestamp when SOGS will expire and delete the message
        public let expires: TimeInterval
        
        /// The encrypted message body
        public let base64EncodedMessage: String
    }
}
