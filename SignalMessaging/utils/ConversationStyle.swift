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

    // TODO:
    @objc
    public let bubbleColorOutgoingUnsent = UIColor.ows_red

    // TODO:
    @objc
    public let bubbleColorOutgoingSending = UIColor.ows_light35

    @objc
    public let bubbleColorOutgoingSent = UIColor.ows_light10

    @objc
    public var primaryColor: UIColor

    @objc
    public func bubbleColor(message: TSMessage) -> UIColor {
        if message is TSIncomingMessage {
            return primaryColor
        } else if let outgoingMessage = message as? TSOutgoingMessage {
            switch outgoingMessage.messageState {
            case .failed:
                return self.bubbleColorOutgoingUnsent
            case .sending:
                return self.bubbleColorOutgoingSending
            default:
                return self.bubbleColorOutgoingSent
            }
        } else {
            owsFail("Unexpected message type: \(message)")
            return UIColor.ows_materialBlue
        }
    }

    @objc
    public func bubbleColor(call: TSCall) -> UIColor {
        if call.isIncoming {
            return primaryColor
        } else {
            return self.bubbleColorOutgoingSent
        }
    }

    @objc
    public static var bubbleTextColorIncoming = UIColor.ows_white

    @objc
    public func bubbleTextColor(message: TSMessage) -> UIColor {
        if message is TSIncomingMessage {
            return ConversationStyle.bubbleTextColorIncoming
        } else if let outgoingMessage = message as? TSOutgoingMessage {
            switch outgoingMessage.messageState {
            case .failed:
                return UIColor.ows_black
            case .sending:
                return UIColor.ows_black
            default:
                return UIColor.ows_black
            }
        } else {
            owsFail("Unexpected message type: \(message)")
            return UIColor.ows_materialBlue
        }
    }

    @objc
    public func bubbleTextColor(call: TSCall) -> UIColor {
        if call.isIncoming {
            return ConversationStyle.bubbleTextColorIncoming
        } else {
            return UIColor.ows_black
        }
    }
}
