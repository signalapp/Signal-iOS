//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@objcMembers
public class TSErrorMessageBuilder: TSMessageBuilder {
    public let errorType: TSErrorMessageType
    public var recipientAddress: SignalServiceAddress?
    public var senderAddress: SignalServiceAddress?
    public var wasIdentityVerified: Bool = false

    private init(
        thread: TSThread,
        errorType: TSErrorMessageType
    ) {
        self.errorType = errorType

        super.init(
            thread: thread,
            timestamp: nil,
            receivedAtTimestamp: nil,
            messageBody: nil,
            bodyRanges: nil,
            editState: .none,
            expiresInSeconds: nil,
            expireStartedAt: nil,
            isViewOnceMessage: false,
            read: false,
            storyAuthorAci: nil,
            storyTimestamp: nil,
            storyReactionEmoji: nil,
            giftBadge: nil
        )
    }

    // MARK: -

    public class func errorMessageBuilder(
        thread: TSThread,
        errorType: TSErrorMessageType
    ) -> TSErrorMessageBuilder {
        return TSErrorMessageBuilder(thread: thread, errorType: errorType)
    }

    // MARK: -

    private var hasBuilt = false

    public func build() -> TSErrorMessage {
        if hasBuilt {
            owsFailDebug("Don't build more than once.")
        }

        hasBuilt = true

        return TSErrorMessage(errorMessageWithBuilder: self)
    }
}
