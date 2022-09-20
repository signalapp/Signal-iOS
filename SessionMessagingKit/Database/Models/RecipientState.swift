// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SignalCoreKit
import SessionUtilitiesKit
import SessionUIKit

public struct RecipientState: Codable, Equatable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "recipientState" }
    internal static let profileForeignKey = ForeignKey([Columns.recipientId], to: [Profile.Columns.id])
    internal static let interactionForeignKey = ForeignKey([Columns.interactionId], to: [Interaction.Columns.id])
    private static let profile = hasOne(Profile.self, using: profileForeignKey)
    internal static let interaction = belongsTo(Interaction.self, using: interactionForeignKey)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression {
        case interactionId
        case recipientId
        case state
        case readTimestampMs
        case mostRecentFailureText
    }
    
    public enum State: Int, Codable, Hashable, DatabaseValueConvertible {
        /// These cases **MUST** remain in this order (even though having `failed` as `0` would be more logical) as the order
        /// is optimised for the desired "interactionState" grouping behaviour we want which makes the query to retrieve the interaction
        /// state run ~16 times than the alternate approach which required a sub-query (check git history to see the old approach at the
        /// bottom of this file if desired)
        ///
        /// The expected behaviour of the grouped "interactionState" that both the `SessionThreadViewModel` and
        /// `MessageViewModel` should use is `IFNULL(MIN("recipientState"."state"), 'sending')` (joining on the
        /// `interaction.id` and `state != 'skipped'`):
        ///  - The 'skipped' state should be ignored entirely
        ///  - If there is no state (ie. interaction recipient records not yet created) then the interaction state should be 'sending'
        ///  - If there is a single 'sending' state then the interaction state should be 'sending'
        ///  - If there is a single 'failed' state and no 'sending' state then the interaction state should be 'failed'
        ///  - If there are neither 'sending' or 'failed' states then the interaction state should be 'sent'
        case sending
        case failed
        case skipped
        case sent
        
        func message(hasAttachments: Bool, hasAtLeastOneReadReceipt: Bool) -> String {
            switch self {
                case .sending:
                    guard hasAttachments else {
                        return "MESSAGE_STATUS_SENDING".localized()
                    }
                    
                    return "MESSAGE_STATUS_UPLOADING".localized()
                
                case .failed: return "MESSAGE_STATUS_FAILED".localized()
                    
                case .sent:
                    guard hasAtLeastOneReadReceipt else {
                        return "MESSAGE_STATUS_SENT".localized()
                    }
                    
                    return "MESSAGE_STATUS_READ".localized()
                    
                default:
                    owsFailDebug("Message has unexpected status: \(self).")
                    return "MESSAGE_STATUS_SENT".localized()
            }
        }
        
        public func statusIconInfo(variant: Interaction.Variant, hasAtLeastOneReadReceipt: Bool) -> (image: UIImage?, themeTintColor: ThemeValue) {
            guard variant == .standardOutgoing else { return (nil, .textPrimary) }

            switch (self, hasAtLeastOneReadReceipt) {
                case (.sending, _): return (UIImage(systemName: "ellipsis.circle"), .textPrimary)
                case (.sent, false), (.skipped, _):
                    return (UIImage(systemName: "checkmark.circle"), .textPrimary)
                    
                case (.sent, true): return (UIImage(systemName: "checkmark.circle.fill"), .textPrimary)
                case (.failed, _): return (UIImage(systemName: "exclamationmark.circle"), .danger)
            }
        }
    }
    
    /// The id for the interaction this state belongs to
    public let interactionId: Int64
    
    /// The id for the recipient that has this state
    ///
    /// **Note:** For contact and closedGroup threads this can be used as a lookup for a contact/profile but in an
    /// openGroup thread this will be the threadId so won’t resolve to a contact/profile
    public let recipientId: String
    
    /// The current state for the recipient
    public let state: State
    
    /// When the interaction was read in milliseconds since epoch
    ///
    /// This value will be null for outgoing messages
    ///
    /// **Note:** This currently will be set when opening the thread for the first time after receiving this interaction
    /// rather than when the interaction actually appears on the screen
    public let readTimestampMs: Int64?
    
    public let mostRecentFailureText: String?
    
    // MARK: - Relationships
         
    public var interaction: QueryInterfaceRequest<Interaction> {
        request(for: RecipientState.interaction)
    }
    
    public var profile: QueryInterfaceRequest<Profile> {
        request(for: RecipientState.profile)
    }
    
    // MARK: - Initialization
    
    public init(
        interactionId: Int64,
        recipientId: String,
        state: State,
        readTimestampMs: Int64? = nil,
        mostRecentFailureText: String? = nil
    ) {
        self.interactionId = interactionId
        self.recipientId = recipientId
        self.state = state
        self.readTimestampMs = readTimestampMs
        self.mostRecentFailureText = mostRecentFailureText
    }
}

// MARK: - Mutation

public extension RecipientState {
    func with(
        state: State? = nil,
        readTimestampMs: Int64? = nil,
        mostRecentFailureText: String? = nil
    ) -> RecipientState {
        return RecipientState(
            interactionId: interactionId,
            recipientId: recipientId,
            state: (state ?? self.state),
            readTimestampMs: (readTimestampMs ?? self.readTimestampMs),
            mostRecentFailureText: (mostRecentFailureText ?? self.mostRecentFailureText)
        )
    }
}
