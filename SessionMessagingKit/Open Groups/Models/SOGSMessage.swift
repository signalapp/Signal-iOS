// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUtilitiesKit

extension OpenGroupAPI {
    public struct Message: Codable, Equatable {
        enum CodingKeys: String, CodingKey {
            case id
            case sender = "session_id"
            case posted
            case edited
            case deleted
            case seqNo = "seqno"
            case whisper
            case whisperMods = "whisper_mods"
            case whisperTo = "whisper_to"
            
            case base64EncodedData = "data"
            case base64EncodedSignature = "signature"
            
            case reactions = "reactions"
        }

        public let id: Int64
        public let sender: String?
        public let posted: TimeInterval?
        public let edited: TimeInterval?
        public let deleted: Bool?
        public let seqNo: Int64
        public let whisper: Bool
        public let whisperMods: Bool
        public let whisperTo: String?
        
        public let base64EncodedData: String?
        public let base64EncodedSignature: String?
        
        public struct Reaction: Codable, Equatable {
            enum CodingKeys: String, CodingKey {
                case count
                case reactors
                case you
                case index
            }
            
            public let count: Int64
            public let reactors: [String]?
            public let you: Bool
            public let index: Int64
        }
        
        public let reactions: [String:Reaction]?
    }
}

// MARK: - Decoder

extension OpenGroupAPI.Message {
    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
    
        let maybeSender: String? = try? container.decode(String.self, forKey: .sender)
        let maybeBase64EncodedData: String? = try? container.decode(String.self, forKey: .base64EncodedData)
        let maybeBase64EncodedSignature: String? = try? container.decode(String.self, forKey: .base64EncodedSignature)
        let maybeReactions: [String:Reaction]? = try? container.decode([String:Reaction].self, forKey: .reactions)
        
        // If we have data and a signature (ie. the message isn't a deletion) then validate the signature
        if let base64EncodedData: String = maybeBase64EncodedData, let base64EncodedSignature: String = maybeBase64EncodedSignature {
            guard let sender: String = maybeSender, let data = Data(base64Encoded: base64EncodedData), let signature = Data(base64Encoded: base64EncodedSignature) else {
                throw HTTP.Error.parsingFailed
            }
            guard let dependencies: SMKDependencies = decoder.userInfo[Dependencies.userInfoKey] as? SMKDependencies else {
                throw HTTP.Error.parsingFailed
            }
            
            // Verify the signature based on the SessionId.Prefix type
            let publicKey: Data = Data(hex: sender.removingIdPrefixIfNeeded())
            
            switch SessionId.Prefix(from: sender) {
                case .blinded:
                    guard dependencies.sign.verify(message: data.bytes, publicKey: publicKey.bytes, signature: signature.bytes) else {
                        SNLog("Ignoring message with invalid signature.")
                        throw HTTP.Error.parsingFailed
                    }
                    
                case .standard, .unblinded:
                    guard (try? dependencies.ed25519.verifySignature(signature, publicKey: publicKey, data: data)) == true else {
                        SNLog("Ignoring message with invalid signature.")
                        throw HTTP.Error.parsingFailed
                    }
                    
                case .none:
                    SNLog("Ignoring message with invalid sender.")
                    throw HTTP.Error.parsingFailed
            }
        }
        
        self = OpenGroupAPI.Message(
            id: try container.decode(Int64.self, forKey: .id),
            sender: try? container.decode(String.self, forKey: .sender),
            posted: try? container.decode(TimeInterval.self, forKey: .posted),
            edited: try? container.decode(TimeInterval.self, forKey: .edited),
            deleted: try? container.decode(Bool.self, forKey: .deleted),
            seqNo: try container.decode(Int64.self, forKey: .seqNo),
            whisper: ((try? container.decode(Bool.self, forKey: .whisper)) ?? false),
            whisperMods: ((try? container.decode(Bool.self, forKey: .whisperMods)) ?? false),
            whisperTo: try? container.decode(String.self, forKey: .whisperTo),
            base64EncodedData: maybeBase64EncodedData,
            base64EncodedSignature: maybeBase64EncodedSignature,
            reactions: !container.contains(.reactions) ? nil : (maybeReactions ?? [:])
        )
    }
}

extension OpenGroupAPI.Message.Reaction {
    public init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)

        self = OpenGroupAPI.Message.Reaction(
            count: try container.decode(Int64.self, forKey: .count),
            reactors: try? container.decode([String].self, forKey: .reactors),
            you: (try? container.decode(Bool.self, forKey: .you)) ?? false,
            index: (try container.decode(Int64.self, forKey: .index))
        )
    }
}
