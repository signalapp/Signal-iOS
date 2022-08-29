// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation

extension OpenGroupAPI {
    public struct PendingChange: Equatable {
        public enum ChangeType {
            case reaction
        }
        
        public enum ReactAction: Equatable {
            case add
            case remove
            case removeAll
        }
        
        enum Metadata {
            case reaction(messageId: Int64, emoji: String, action: ReactAction)
        }
        
        let server: String
        let room: String
        let changeType: ChangeType
        var seqNo: Int64?
        let metadata: Metadata
        
        public static func == (lhs: OpenGroupAPI.PendingChange, rhs: OpenGroupAPI.PendingChange) -> Bool {
            guard lhs.server == rhs.server &&
                    lhs.room == rhs.room &&
                    lhs.changeType == rhs.changeType &&
                    lhs.seqNo == rhs.seqNo
            else {
                return false
            }
            
            switch lhs.changeType {
                case .reaction:
                    if case .reaction(let lhsMessageId, let lhsEmoji, let lhsAction) = lhs.metadata,
                       case .reaction(let rhsMessageId, let rhsEmoji, let rhsAction) = rhs.metadata {
                        return lhsMessageId == rhsMessageId && lhsEmoji == rhsEmoji && lhsAction == rhsAction
                    } else {
                        return false
                    }
            }
        }
    }
}
