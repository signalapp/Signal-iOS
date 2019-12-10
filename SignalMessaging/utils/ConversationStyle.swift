//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class ConversationStyle: NSObject {

    private let thread: TSThread

    // The width of the collection view.
    @objc public var viewWidth: CGFloat = 0 {
        didSet {
            AssertIsOnMainThread()

            updateProperties()
        }
    }

    @objc public let contentMarginTop: CGFloat = 24 // Values.largeSpacing
    @objc public let contentMarginBottom: CGFloat = 24 // Values.largeSpacing

    @objc public var gutterLeading: CGFloat = 0
    @objc public var gutterTrailing: CGFloat = 0

    @objc public var headerGutterLeading: CGFloat = 35 // Values.veryLargeSpacing
    @objc public var headerGutterTrailing: CGFloat = 35 // Values.veryLargeSpacing

    // These are the gutters used by "full width" views
    // like "contact offer" and "info message".
    @objc public var fullWidthGutterLeading: CGFloat = 0
    @objc public var fullWidthGutterTrailing: CGFloat = 0

    @objc public var errorGutterTrailing: CGFloat = 0

    @objc public var contentWidth: CGFloat {
        return viewWidth - (gutterLeading + gutterTrailing)
    }

    @objc public var fullWidthContentWidth: CGFloat {
       return viewWidth - (fullWidthGutterLeading + fullWidthGutterTrailing)
    }

    @objc public var headerViewContentWidth: CGFloat {
        return viewWidth - (headerGutterLeading + headerGutterTrailing)
    }

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
        self.conversationColor = ConversationStyle.conversationColor(thread: thread)

        super.init()

        updateProperties()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(uiContentSizeCategoryDidChange),
                                               name: UIContentSizeCategory.didChangeNotification,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func uiContentSizeCategoryDidChange() {
        AssertIsOnMainThread()

        updateProperties()
    }

    // MARK: -

    @objc
    public func updateProperties() {
        if thread.isGroupThread() {
            gutterLeading = 16 + 35 + 24 // Values.mediumSpacing + Values.smallProfilePictureSize + Values.largeSpacing
            gutterTrailing = 16
        } else {
            gutterLeading = 16
            gutterTrailing = 16
        }
        fullWidthGutterLeading = 16
        fullWidthGutterTrailing = 16
        headerGutterLeading = 16
        headerGutterTrailing = 16
        errorGutterTrailing = 16

        maxMessageWidth = floor(contentWidth - 32)

        let messageTextFont = UIFont.systemFont(ofSize: 13) // Values.smallFontSize

        let baseFontOffset: CGFloat = 16

        // Don't include the distance from the "cap height" to the top of the UILabel
        // in the top margin.
        textInsetTop = max(0, round(baseFontOffset - (messageTextFont.ascender - messageTextFont.capHeight)))
        // Don't include the distance from the "baseline" to the bottom of the UILabel
        // (e.g. the descender) in the top margin. Note that UIFont.descender is a
        // negative value.
        textInsetBottom = max(0, round(baseFontOffset - abs(messageTextFont.descender)))

        textInsetHorizontal = 16

        lastTextLineAxis = CGFloat(round(baseFontOffset + messageTextFont.capHeight * 0.5))

        self.conversationColor = ConversationStyle.conversationColor(thread: thread)
    }

    // MARK: Colors

    @objc
    public var conversationColor: OWSConversationColor

    private class func conversationColor(thread: TSThread) -> OWSConversationColor {
        let colorName = thread.conversationColorName

        return OWSConversationColor.conversationColorOrDefault(colorName: colorName)
    }

    @objc
    private static var defaultBubbleColorIncoming: UIColor {
        return UIColor(rgbHex: 0x222325) // Colors.receivedMessageBackgroundColor
    }

    @objc
    public let bubbleColorOutgoingFailed = UIColor(rgbHex: 0x3F4146) // Colors.sentMessageBackgroundColor

    @objc
    public let bubbleColorOutgoingSending = UIColor(rgbHex: 0x3F4146) // Colors.sentMessageBackgroundColor

    @objc
    public let bubbleColorOutgoingSent = UIColor(rgbHex: 0x3F4146) // Colors.sentMessageBackgroundColor

    @objc
    public let dateBreakTextColor = UIColor.ows_gray60

    @objc
    public func bubbleColor(message: TSMessage) -> UIColor {
        if message is TSIncomingMessage {
            return ConversationStyle.defaultBubbleColorIncoming
        } else if let outgoingMessage = message as? TSOutgoingMessage {
            switch outgoingMessage.messageState {
            case .failed:
                return bubbleColorOutgoingFailed
            case .sending:
                return bubbleColorOutgoingSending
            default:
                return bubbleColorOutgoingSent
            }
        } else {
            owsFailDebug("Unexpected message type: \(message)")
            return bubbleColorOutgoingSent
        }
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
    public static var bubbleTextColorIncoming: UIColor {
        return UIColor(rgbHex: 0xFFFFFF) // Colors.text
    }

    @objc
    public static var bubbleTextColorOutgoing: UIColor {
        return UIColor(rgbHex: 0xFFFFFF) // Colors.text
    }

    @objc
    public func bubbleTextColor(message: TSMessage) -> UIColor {
        if message is TSIncomingMessage {
            return ConversationStyle.bubbleTextColorIncoming
        } else if message is TSOutgoingMessage {
            return ConversationStyle.bubbleTextColorOutgoing
        } else {
            owsFailDebug("Unexpected message type: \(message)")
            return ConversationStyle.bubbleTextColorOutgoing
        }
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
        return bubbleTextColor(isIncoming: isIncoming).withAlphaComponent(0.6) // Values.unimportantElementOpacity
    }

    @objc
    public func quotedReplyBubbleColor(isIncoming: Bool) -> UIColor {
        if isIncoming {
            return UIColor(rgbHex: 0x3F4146) // Colors.sentMessageBackgroundColor
        } else {
            return UIColor(rgbHex: 0x222325) // Colors.receivedMessageBackgroundColor
        }
    }

    @objc
    public func quotedReplyStripeColor(isIncoming: Bool) -> UIColor {
        return UIColor(rgbHex: 0x00F782) // Colors.accent
    }

    @objc
    public func quotingSelfHighlightColor() -> UIColor {
        // TODO:
        return UIColor.init(rgbHex: 0xFF0000)
    }

    @objc
    public func quotedReplyAuthorColor() -> UIColor {
        return UIColor(rgbHex: 0xFFFFFF) // Colors.text
    }

    @objc
    public func quotedReplyTextColor() -> UIColor {
        return UIColor(rgbHex: 0xFFFFFF) // Colors.text
    }

    @objc
    public func quotedReplyAttachmentColor() -> UIColor {
        return UIColor(rgbHex: 0xFFFFFF) // Colors.text
    }
}
