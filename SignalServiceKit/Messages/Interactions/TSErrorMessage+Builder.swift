//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@objc
public class TSErrorMessageBuilder: TSMessageBuilder {
    @objc
    public let errorType: TSErrorMessageType
    @objc
    public var recipientAddress: SignalServiceAddress?
    @objc
    public var senderAddress: SignalServiceAddress?
    @objc
    public var wasIdentityVerified: Bool = false

    private init(
        thread: TSThread,
        errorType: TSErrorMessageType
    ) {
        self.errorType = errorType

        super.init(
            thread: thread,
            timestamp: nil,
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

    @objc
    public class func errorMessageBuilder(
        thread: TSThread,
        errorType: TSErrorMessageType
    ) -> TSErrorMessageBuilder {
        return TSErrorMessageBuilder(thread: thread, errorType: errorType)
    }

    // MARK: -

    private var hasBuilt = false

    @objc
    public func build() -> TSErrorMessage {
        if hasBuilt {
            owsFailDebug("Don't build more than once.")
        }

        hasBuilt = true

        return TSErrorMessage(errorMessageWithBuilder: self)
    }
}
