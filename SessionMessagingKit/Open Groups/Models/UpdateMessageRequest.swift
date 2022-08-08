// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    public struct UpdateMessageRequest: Codable {
        /// The serialized message body (encoded in base64 when encoding)
        let data: Data
        
        /// A 64-byte Ed25519 signature of the message body, signed by the current user's keys (encoded in base64 when
        /// encoding - ie. 88 base64 chars)
        let signature: Data
        
        /// Array of file IDs of new files uploaded as attachments of this post
        ///
        /// This is required to preserve uploads for the default expiry period (15 days, unless otherwise configured by the SOGS
        /// administrator); uploaded files that are not attached to a post will be deleted much sooner
        ///
        /// If any of the given file ids are already associated with another message then the association is ignored (i.e. the files remain
        /// associated with the original message)
        ///
        /// This field must contain the IDs of any newly uploaded files that are part of the edit; existing attachment IDs may also be
        /// included, but are not required
        let fileIds: [Int64]?
        
        // MARK: - Encodable
        
        public func encode(to encoder: Encoder) throws {
            var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(data.base64EncodedString(), forKey: .data)
            try container.encode(signature.base64EncodedString(), forKey: .signature)
        }
    }
}
