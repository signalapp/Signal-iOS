//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class ConversationStyle: NSObject {

    private let thread: TSThread

    // The width of the collection view.
    @objc public var viewWidth: CGFloat = 0 {
        didSet {
            SwiftAssertIsOnMainThread(#function)

            updateProperties()
        }
    }

    @objc public let contentMarginTop: CGFloat = 24
    @objc public let contentMarginBottom: CGFloat = 24

    @objc public var gutterLeading: CGFloat = 0
    @objc public var gutterTrailing: CGFloat = 0
    // These are the gutters used by "full width" views
    // like "date headers" and "unread indicator".
    @objc public var fullWidthGutterLeading: CGFloat = 0
    @objc public var fullWidthGutterTrailing: CGFloat = 0
    @objc public var errorGutterTrailing: CGFloat = 0

    // viewWidth - (gutterLeading + gutterTrailing)
    @objc public var contentWidth: CGFloat = 0

    // viewWidth - (gutterfullWidthGutterLeadingLeading + fullWidthGutterTrailing)
    @objc public var fullWidthContentWidth: CGFloat = 0

    @objc public var maxMessageWidth: CGFloat = 0

    @objc public var textInsetTop: CGFloat = 0
    @objc public var textInsetBottom: CGFloat = 0
    @objc public var textInsetHorizontal: CGFloat = 0

    // We want to align "group sender" avatars with the v-center of the
    // "last line" of the message body text - or where it would be for
    // non-text content.
    //
    // This is the distance from that v-center to the bottom of the
    // message bubble.
    @objc public var lastTextLineAxis: CGFloat = 0

    @objc
    public required init(thread: TSThread) {

        self.thread = thread
        self.primaryColor = ConversationStyle.primaryColor(thread: thread)

        super.init()

        updateProperties()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(uiContentSizeCategoryDidChange),
                                               name: NSNotification.Name.UIContentSizeCategoryDidChange,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func uiContentSizeCategoryDidChange() {
        SwiftAssertIsOnMainThread(#function)

        updateProperties()
    }

    // MARK: -

    @objc
    public func updateProperties() {
        if thread.isGroupThread() {
            gutterLeading = 52
            gutterTrailing = 20
        } else {
            gutterLeading = 16
            gutterTrailing = 20
        }
        fullWidthGutterLeading = gutterLeading
        fullWidthGutterTrailing = gutterTrailing
        errorGutterTrailing = 16

        contentWidth = viewWidth - (gutterLeading + gutterTrailing)

        fullWidthContentWidth = viewWidth - (fullWidthGutterLeading + fullWidthGutterTrailing)

        maxMessageWidth = floor(contentWidth - 48)

        let messageTextFont = UIFont.ows_dynamicTypeBody

        let baseFontOffset: CGFloat = 11

        // Don't include the distance from the "cap height" to the top of the UILabel
        // in the top margin.
        textInsetTop = max(0, round(baseFontOffset - (messageTextFont.ascender - messageTextFont.capHeight)))
        // Don't include the distance from the "baseline" to the bottom of the UILabel
        // (e.g. the descender) in the top margin. Note that UIFont.descender is a
        // negative value.
        textInsetBottom = max(0, round(baseFontOffset - abs(messageTextFont.descender)))

        if _isDebugAssertConfiguration(), UIFont.ows_dynamicTypeBody.pointSize == 17 {
            assert(textInsetTop == 7)
            assert(textInsetBottom == 7)
        }

        textInsetHorizontal = 12

        lastTextLineAxis = CGFloat(round(baseFontOffset + messageTextFont.capHeight * 0.5))

        self.primaryColor = ConversationStyle.primaryColor(thread: thread)
    }

    // MARK: Colors

    private class func primaryColor(thread: TSThread) -> UIColor {
        guard let colorName = thread.conversationColorName else {
            return self.defaultBubbleColorIncoming
        }

        guard let color = UIColor.ows_conversationColor(colorName: colorName) else {
            return self.defaultBubbleColorIncoming
        }

        return color
    }

    private static let defaultBubbleColorIncoming = UIColor.ows_messageBubbleLightGray

    @objc
    public let bubbleColorOutgoingUnsent = UIColor.gray

    @objc
    public let bubbleColorOutgoingSending = UIColor.ows_fadedBlue

    @objc
    public let bubbleColorOutgoingSent = UIColor.ows_materialBlue

    @objc
    public var primaryColor: UIColor

    @objc
    public func bubbleColor(message: TSMessage) -> UIColor {
        if message is TSIncomingMessage {
            return ConversationStyle.defaultBubbleColorIncoming
        } else if let outgoingMessage = message as? TSOutgoingMessage {
            switch outgoingMessage.messageState {
            case .failed:
                return bubbleColorOutgoingUnsent
            case .sending:
                return bubbleColorOutgoingSending
            default:
                return bubbleColorOutgoingSent
            }
        } else {
            owsFail("Unexpected message type: \(message)")
            return bubbleColorOutgoingSent
        }
    }

    @objc
    public func bubbleColor(call: TSCall) -> UIColor {
        return bubbleColor(isIncoming: call.isIncoming)
    }

    @objc
    public func bubbleColor(isIncoming: Bool) -> UIColor {
        if isIncoming {
            return ConversationStyle.defaultBubbleColorIncoming
        } else {
            return self.bubbleColorOutgoingSent
        }
    }

    @objc
    public static var bubbleTextColorIncoming = UIColor.ows_black
    public static var bubbleTextColorOutgoing = UIColor.ows_white

    @objc
    public func bubbleTextColor(message: TSMessage) -> UIColor {
        if message is TSIncomingMessage {
            return ConversationStyle.bubbleTextColorIncoming
        } else if let _ = message as? TSOutgoingMessage {
            return ConversationStyle.bubbleTextColorOutgoing
        } else {
            owsFail("Unexpected message type: \(message)")
            return ConversationStyle.bubbleTextColorOutgoing
        }
    }

    @objc
    public func bubbleTextColor(call: TSCall) -> UIColor {
        return bubbleTextColor(isIncoming: call.isIncoming)
    }

    @objc
    public func bubbleTextColor(isIncoming: Bool) -> UIColor {
        if isIncoming {
            return ConversationStyle.bubbleTextColorIncoming
        } else {
            return ConversationStyle.bubbleTextColorOutgoing
        }
    }

    @objc
    public func bubbleSecondaryTextColor(isIncoming: Bool) -> UIColor {
        return bubbleTextColor(isIncoming: isIncoming).withAlphaComponent(0.7)
    }

    @objc
    public func quotedReplyBubbleColor(isIncoming: Bool) -> UIColor {
        // TODO: Values
        // TODO: Should this reflect "quoting self" v. "quoting other"?

        if isIncoming {
            return bubbleColorOutgoingSent.withAlphaComponent(0.7)
        } else {
            return ConversationStyle.defaultBubbleColorIncoming.withAlphaComponent(0.7)
        }
    }

    @objc
    public func quotedReplyStripeColor(isIncoming: Bool) -> UIColor {
        // TODO: Values
        // TODO: Should this reflect "quoting self" v. "quoting other"?

        if isIncoming {
            return bubbleColorOutgoingSent
        } else {
            return ConversationStyle.defaultBubbleColorIncoming
        }
    }

    @objc
    public func quotingSelfHighlightColor() -> UIColor {
        // TODO:
        return UIColor.init(rgbHex: 0xB5B5B5)
    }

    @objc
    public func quotedReplyAuthorColor() -> UIColor {
        // TODO:
        return UIColor.ows_light90
    }

    @objc
    public func quotedReplyTextColor() -> UIColor {
        // TODO:
        return UIColor.ows_light90
    }

    @objc
    public func quotedReplyAttachmentColor() -> UIColor {
        // TODO:
        return UIColor(white: 0.5, alpha: 1.0)
    }
}
