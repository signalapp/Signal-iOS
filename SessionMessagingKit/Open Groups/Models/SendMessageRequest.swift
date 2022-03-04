// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    public struct SendMessageRequest: Codable {
        enum CodingKeys: String, CodingKey {
            case data
            case signature
            case whisperTo = "whisper_to"
            case whisperMods = "whisper_mods"
            case fileIds = "files"
        }
        
        /// The serialized message body (encoded in base64 when encoding)
        let data: Data
        
        /// A 64-byte Ed25519 signature of the message body, signed by the current user's keys (encoded in base64 when
        /// encoding - ie. 88 base64 chars)
        let signature: Data
        
        /// If present this indicates that this message is a whisper that should only be shown to the given user (via their sessionId)
        let whisperTo: String?
        
        /// If `true`, then this message will be visible to moderators but not ordinary users
        ///
        /// If this and `whisper_to` are used together then the message will be visible to the given user and any room
        /// moderators (this can be used, for instance, to issue a warning to a user that only the user and other mods can see)
        ///
        /// **Note:** Only moderators may set this flag
        let whisperMods: Bool?
        
        /// Array of file IDs of new files uploaded as attachments of this post
        ///
        /// This is required to preserve uploads for the default expiry period (15 days, unless otherwise configured by the SOGS
        /// administrator); uploaded files that are not attached to a post will be deleted much sooner
        ///
        /// If any of the given file ids are already associated with another message then the association is ignored (i.e. the files remain
        /// associated with the original message)
        ///
        /// When submitting a message edit this field must contain the IDs of any newly uploaded files that are part of the edit; existing
        /// attachment IDs may also be included, but are not required
        ///
        /// **Note:** The SOGS API actually expects an array of Int64 (ie. what is returned when uploading a file to SOGS) but
        /// when uploading direct to the FileServer we get a string id back. In order to avoid supporting both cases we convert
        /// the id returned by SOGS to a string and send those through - luckily SOGS converts the values to ints so supports
        /// receipving an array of String values
        let fileIds: [String]?
        
        // MARK: - Initialization
        
        init(
            data: Data,
            signature: Data,
            whisperTo: String? = nil,
            whisperMods: Bool? = nil,
            fileIds: [String]? = nil
        ) {
            self.data = data
            self.signature = signature
            self.whisperTo = whisperTo
            self.whisperMods = whisperMods
            self.fileIds = fileIds
        }
        
        // MARK: - Encodable
        
        public func encode(to encoder: Encoder) throws {
            var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
            
            try container.encode(data.base64EncodedString(), forKey: .data)
            try container.encode(signature.base64EncodedString(), forKey: .signature)
            try container.encodeIfPresent(whisperTo, forKey: .whisperTo)
            try container.encodeIfPresent(whisperMods, forKey: .whisperMods)
            try container.encodeIfPresent(fileIds, forKey: .fileIds)
        }
    }
}
