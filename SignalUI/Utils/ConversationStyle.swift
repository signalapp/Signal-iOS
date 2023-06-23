//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

// An immutable snapshot of the core styling
// state used by CVC for a given load/render cycle.
public class ConversationStyle: NSObject {

    public enum `Type`: UInt {
        // The style used from initialization until presentation begins.
        // It does not have valid values and should not be rendered.
        case initial
        // The style used until the presentation has configured the view(s).
        // It has values inferred from the navigationController.
        case placeholder
        // The style once presentation has configured the view(s).
        // It has values from the CVC view state.
        case `default`
        // The style used in the message detail view
        case messageDetails

        fileprivate var isValid: Bool { self != .initial }
    }

    public let type: `Type`

    public var isValidStyle: Bool { type.isValid }

    // The width of the collection view.
    public let viewWidth: CGFloat

    public let isDarkThemeEnabled: Bool

    public let hasWallpaper: Bool

    public let isWallpaperPhoto: Bool

    private let dynamicBodyTypePointSize: CGFloat
    private let primaryTextColor: UIColor

    public let contentMarginTop: CGFloat = 24
    public let contentMarginBottom: CGFloat = 24

    public let gutterLeading: CGFloat
    public let gutterTrailing: CGFloat

    public let headerGutterLeading: CGFloat = 28
    public let headerGutterTrailing: CGFloat = 28

    // These are the gutters used by "full width" views
    // like "contact offer" and "info message".
    public let fullWidthGutterLeading: CGFloat
    public let fullWidthGutterTrailing: CGFloat

    static public let groupMessageAvatarSizeClass = ConversationAvatarView.Configuration.SizeClass.twentyEight
    static public let selectionViewWidth: CGFloat = 24
    static public let messageStackSpacing: CGFloat = 8
    static public let defaultMessageSpacing: CGFloat = 12
    static public let compactMessageSpacing: CGFloat = 2
    static public let systemMessageSpacing: CGFloat = 20

    public let contentWidth: CGFloat

    public var headerViewContentWidth: CGFloat {
        viewWidth - (headerGutterLeading + headerGutterTrailing)
    }

    public let maxMessageWidth: CGFloat
    public let maxMediaMessageWidth: CGFloat
    public let maxAudioMessageWidth: CGFloat

    public let textInsetTop: CGFloat
    public let textInsetBottom: CGFloat
    public let textInsetHorizontal: CGFloat
    public var textInsets: UIEdgeInsets {
        UIEdgeInsets(top: textInsetTop,
                     leading: textInsetHorizontal,
                     bottom: textInsetBottom,
                     trailing: textInsetHorizontal)
    }

    // We want to align "group sender" avatars with the v-center of the
    // "last line" of the message body text - or where it would be for
    // non-text content.
    //
    // This is the distance from that v-center to the bottom of the
    // message bubble.
    public let lastTextLineAxis: CGFloat

    // Incoming and outgoing messages are visually distinguished
    // by leading and trailing alignment, respectively.
    //
    // Reserve a space so that in the most compressed layouts
    // (small form factor, group avatar, multi-select, etc.)
    // there is space for them to align in these directions.
    public static let messageDirectionSpacing: CGFloat = 12

    // ChatColor is used for persistence, logging and comparison.
    public let chatColor: ChatColor
    // ColorOrGradientValue is used for rendering.
    public let chatColorValue: ColorOrGradientValue

    public required init(type: `Type`,
                         thread: TSThread,
                         viewWidth: CGFloat,
                         hasWallpaper: Bool,
                         isWallpaperPhoto: Bool,
                         chatColor: ChatColor) {

        self.type = type
        self.viewWidth = viewWidth
        self.isDarkThemeEnabled = Theme.isDarkThemeEnabled
        self.primaryTextColor = Theme.primaryTextColor
        self.hasWallpaper = hasWallpaper
        self.isWallpaperPhoto = isWallpaperPhoto
        self.chatColor = chatColor
        self.chatColorValue = chatColor.setting.asValue

        if type == .messageDetails {
            gutterLeading = 0
            gutterTrailing = 0
            fullWidthGutterLeading = 0
            fullWidthGutterTrailing = 0
        } else {
            gutterLeading = thread.isGroupThread ? 12 : 16
            gutterTrailing = 16

            fullWidthGutterLeading = thread.isGroupThread ? 12 : 16
            fullWidthGutterTrailing = thread.isGroupThread ? 12 : 16
        }

        let messageTextFont = UIFont.dynamicTypeBody

        dynamicBodyTypePointSize = messageTextFont.pointSize

        let baseFontOffset: CGFloat = 11

        // Don't include the distance from the "cap height" to the top of the UILabel
        // in the top margin.
        textInsetTop = max(0, round(baseFontOffset - (messageTextFont.ascender - messageTextFont.capHeight)))
        // Don't include the distance from the "baseline" to the bottom of the UILabel
        // (e.g. the descender) in the top margin. Note that UIFont.descender is a
        // negative value.
        textInsetBottom = max(0, round(baseFontOffset - abs(messageTextFont.descender)))

        textInsetHorizontal = 12

        lastTextLineAxis = CGFloat(round(baseFontOffset + messageTextFont.capHeight * 0.5))

        contentWidth = viewWidth - (gutterLeading + gutterTrailing)

        var maxMessageWidth = contentWidth - (Self.selectionViewWidth + Self.messageStackSpacing)

        maxMessageWidth -= Self.messageDirectionSpacing

        if thread.isGroupThread {
            maxMessageWidth -= (CGFloat(ConversationStyle.groupMessageAvatarSizeClass.size.width) + Self.messageStackSpacing)
        }
        self.maxMessageWidth = maxMessageWidth

        // This upper bound should have no effect in portrait orientation.
        // It limits body media size in landscape.
        let kMaxBodyMediaSize: CGFloat = 350
        maxMediaMessageWidth = floor(min(maxMessageWidth, kMaxBodyMediaSize))

        let kMaxAudioMessageWidth: CGFloat = 244
        maxAudioMessageWidth = floor(min(maxMessageWidth, kMaxAudioMessageWidth))

        super.init()
    }

    // MARK: Colors

    public static func bubbleColorIncoming(hasWallpaper: Bool,
                                           isDarkThemeEnabled: Bool) -> UIColor {
        if hasWallpaper {
            return isDarkThemeEnabled ? .ows_gray95 : .white
        } else {
            return isDarkThemeEnabled ? UIColor.ows_gray80 : UIColor.ows_gray05
        }
    }
    public var bubbleColorIncoming: UIColor {
        Self.bubbleColorIncoming(hasWallpaper: hasWallpaper,
                                 isDarkThemeEnabled: isDarkThemeEnabled)
    }

    public let dateBreakTextColor = UIColor.ows_gray60

    public func bubbleChatColor(isIncoming: Bool) -> ColorOrGradientValue {
        if isIncoming {
            return .solidColor(color: bubbleColorIncoming)
        } else {
            return bubbleChatColorOutgoing
        }
    }

    public var bubbleChatColorOutgoing: ColorOrGradientValue {
        chatColorValue
    }

    public static var bubbleTextColorIncoming: UIColor {
        return bubbleTextColorIncomingThemed.forCurrentTheme
    }

    public static var bubbleTextColorIncomingThemed: ThemedColor {
        ThemedColor(light: UIColor.ows_gray90, dark: UIColor.ows_gray05)
    }

    public static var bubbleTextColorOutgoing: UIColor {
        return bubbleTextColorOutgoingThemed.forCurrentTheme
    }

    public static var bubbleTextColorOutgoingThemed: ThemedColor {
        ThemedColor(light: UIColor.ows_white, dark: UIColor.ows_gray05)
    }

    public var bubbleTextColorIncoming: UIColor {
        Self.bubbleTextColorIncomingThemed.color(isDarkThemeEnabled: isDarkThemeEnabled)
    }

    public var bubbleSecondaryTextColorIncoming: UIColor {
        isDarkThemeEnabled ? .ows_gray25 : .ows_gray60
    }

    public var bubbleTextColorOutgoing: UIColor {
        Self.bubbleTextColorOutgoingThemed.color(isDarkThemeEnabled: isDarkThemeEnabled)
    }

    public var bubbleSecondaryTextColorOutgoing: UIColor {
        isDarkThemeEnabled ? .ows_whiteAlpha60 : .ows_whiteAlpha80
    }

    public func bubbleTextColor(message: TSMessage) -> UIColor {
        if message.wasRemotelyDeleted && !hasWallpaper {
            return primaryTextColor
        } else if message is TSIncomingMessage {
            return bubbleTextColorIncoming
        } else if message is TSOutgoingMessage {
            return bubbleTextColorOutgoing
        } else {
            owsFailDebug("Unexpected message type: \(message)")
            return bubbleTextColorOutgoing
        }
    }

    public func bubbleTextColor(isIncoming: Bool) -> UIColor {
        if isIncoming {
            return bubbleTextColorIncoming
        } else {
            return bubbleTextColorOutgoing
        }
    }

    public func bubbleReadMoreTextColor(message: TSMessage) -> UIColor {
        if message is TSIncomingMessage {
            return isDarkThemeEnabled ? .ows_whiteAlpha90 : .ows_accentBlue
        } else if message is TSOutgoingMessage {
            return isDarkThemeEnabled ? .ows_whiteAlpha90 : .white
        } else {
            owsFailDebug("Unexpected message type: \(message)")
            return bubbleTextColorOutgoing
        }
    }

    public func bubbleSecondaryTextColor(isIncoming: Bool) -> UIColor {
        if isIncoming {
            return bubbleSecondaryTextColorIncoming
        } else {
            return bubbleSecondaryTextColorOutgoing
        }
    }

    // Same across all themes
    public static var searchMatchHighlightColor: UIColor {
        return UIColor.yellow
    }

    public func isEqualForCellRendering(_ other: ConversationStyle) -> Bool {
        // We need to compare any state that could affect
        // how we render view appearance.
        (type.isValid == other.type.isValid &&
            viewWidth == other.viewWidth &&
            dynamicBodyTypePointSize == other.dynamicBodyTypePointSize &&
            isDarkThemeEnabled == other.isDarkThemeEnabled &&
            hasWallpaper == other.hasWallpaper &&
            isWallpaperPhoto == other.isWallpaperPhoto &&
            maxMessageWidth == other.maxMessageWidth &&
            maxMediaMessageWidth == other.maxMediaMessageWidth &&
            textInsets == other.textInsets &&
            gutterLeading == other.gutterLeading &&
            gutterTrailing == other.gutterTrailing &&
            fullWidthGutterLeading == other.fullWidthGutterLeading &&
            fullWidthGutterTrailing == other.fullWidthGutterTrailing &&
            textInsets == other.textInsets &&
            lastTextLineAxis == other.lastTextLineAxis &&
            // We don't need to compare chatColor or all of chatColor;
            // it is sufficient to compare chatColor.setting.
            chatColor.setting == other.chatColor.setting)
    }

    public override var debugDescription: String {
        "[" +
            "type.isValid: \(type.isValid), " +
            "viewWidth: \(viewWidth), " +
            "dynamicBodyTypePointSize: \(dynamicBodyTypePointSize), " +
            "isDarkThemeEnabled: \(isDarkThemeEnabled), " +
            "hasWallpaper: \(hasWallpaper), " +
            "isWallpaperPhoto: \(isWallpaperPhoto), " +
            "maxMessageWidth: \(maxMessageWidth), " +
            "maxMediaMessageWidth: \(maxMediaMessageWidth), " +
            "textInsets: \(textInsets), " +
            "gutterLeading: \(gutterLeading), " +
            "gutterTrailing: \(gutterTrailing), " +
            "fullWidthGutterLeading: \(fullWidthGutterLeading), " +
            "fullWidthGutterTrailing: \(fullWidthGutterTrailing), " +
            "textInsets: \(textInsets), " +
            "lastTextLineAxis: \(lastTextLineAxis), " +
            "chatColor: \(chatColor), " +
            "]"
    }
}

extension ConversationStyle {

    public func quotedReplyHighlightColor() -> UIColor {
        UIColor.init(rgbHex: 0xB5B5B5)
    }

    public func quotedReplyAuthorColor() -> UIColor {
        quotedReplyTextColor()
    }

    public func quotedReplyTextColor() -> UIColor {
        isDarkThemeEnabled ? .ows_gray05 : .ows_gray90
    }

    public func quotedReplyAttachmentColor() -> UIColor {
        isDarkThemeEnabled ? .ows_gray05 : UIColor.ows_gray90
    }
}
