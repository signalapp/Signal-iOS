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
            AssertIsOnMainThread()

            updateProperties()
        }
    }

    @objc public let contentMarginTop: CGFloat = 24
    @objc public let contentMarginBottom: CGFloat = 24

    @objc public var gutterLeading: CGFloat = 0
    @objc public var gutterTrailing: CGFloat = 0

    @objc public var headerGutterLeading: CGFloat = 28
    @objc public var headerGutterTrailing: CGFloat = 28

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
                                               name: NSNotification.Name.UIContentSizeCategoryDidChange,
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
            gutterLeading = 52
            gutterTrailing = 16
        } else {
            gutterLeading = 16
            gutterTrailing = 16
        }
        fullWidthGutterLeading = 16
        fullWidthGutterTrailing = 16
        headerGutterLeading = 28
        headerGutterTrailing = 28
        errorGutterTrailing = 16

        maxMessageWidth = floor(contentWidth - 32)

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
        return Theme.isDarkThemeEnabled ? UIColor.ows_gray75 : UIColor.ows_messageBubbleLightGray
    }

    @objc
    public let dateBreakTextColor = UIColor.ows_gray60

    @objc
    public func bubbleColor(message: TSMessage) -> UIColor {
        if message is TSIncomingMessage {
            return bubbleColor(isIncoming: true)
        } else {
            return bubbleColor(isIncoming: false)
        }
    }

    @objc
    public func bubbleColor(isIncoming: Bool) -> UIColor {
        if isIncoming {
            return ConversationStyle.defaultBubbleColorIncoming
        } else {
            return conversationColor.primaryColor
        }
    }

    @objc
    public static var bubbleTextColorIncoming: UIColor {
        return Theme.isDarkThemeEnabled ? UIColor.ows_gray05 : UIColor.ows_gray90
    }

    @objc
    public static var bubbleTextColorOutgoing: UIColor {
        return Theme.isDarkThemeEnabled ? UIColor.ows_gray05 : UIColor.ows_white
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

    // Note that the exception for outgoing text only applies
    // to secondary text within bubbles.
    @objc
    public func bubbleSecondaryTextColor(isIncoming: Bool) -> UIColor {
        if !isIncoming {
            // All Outgoing
            return UIColor.ows_white.withAlphaComponent(0.8)
        } else if Theme.isDarkThemeEnabled {
            // Incoming, dark.
            return UIColor.ows_gray25
        } else {
            // Incoming, light.
            return UIColor.ows_gray60
        }
    }

    @objc
    public func quotedReplyBubbleColor(isIncoming: Bool) -> UIColor {
        if Theme.isDarkThemeEnabled {
            return conversationColor.shadeColor
        } else {
            return conversationColor.tintColor
        }
    }

    @objc
    public func quotedReplyStripeColor(isIncoming: Bool) -> UIColor {
        if isIncoming {
            return conversationColor.primaryColor
        } else {
            return Theme.backgroundColor
        }
    }

    @objc
    public func quotingSelfHighlightColor() -> UIColor {
        // TODO:
        return UIColor.init(rgbHex: 0xB5B5B5)
    }

    @objc
    public func quotedReplyAuthorColor() -> UIColor {
        return quotedReplyTextColor()
    }

    @objc
    public func quotedReplyTextColor() -> UIColor {
        if Theme.isDarkThemeEnabled {
            return UIColor.ows_gray05
        } else {
            return UIColor.ows_gray90
        }
    }

    @objc
    public func quotedReplyAttachmentColor() -> UIColor {
        // TODO:
        return Theme.middleGrayColor
    }
}
