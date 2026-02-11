//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

// An immutable snapshot of the core styling
// state used by CVC for a given load/render cycle.
public struct ConversationStyle {

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
    // Determines blur effect for incoming message bubbles.
    public let shouldDimWallpaperInDarkMode: Bool
    public let isWallpaperPhoto: Bool

    public let isStandaloneRenderItem: Bool

    private let dynamicBodyTypePointSize: CGFloat
    private let primaryTextColor: UIColor

    public let contentMarginTop: CGFloat = 24
    public let contentMarginBottom: CGFloat = if #available(iOS 26, *) { 8 } else { 24 }

    public let gutterLeading: CGFloat
    public let gutterTrailing: CGFloat

    public let headerGutterLeading: CGFloat = 28
    public let headerGutterTrailing: CGFloat = 28

    // These are the gutters used by "full width" views
    // like "contact offer" and "info message".
    public let fullWidthGutterLeading: CGFloat
    public let fullWidthGutterTrailing: CGFloat

    public static let groupMessageAvatarSizeClass = ConversationAvatarView.Configuration.SizeClass.twentyEight
    public static let selectionViewWidth: CGFloat = 24
    public static let messageStackSpacing: CGFloat = 8
    public static let defaultMessageSpacing: CGFloat = 12
    public static let compactMessageSpacing: CGFloat = 2
    public static let systemMessageSpacing: CGFloat = 20

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
        UIEdgeInsets(
            top: textInsetTop,
            leading: textInsetHorizontal,
            bottom: textInsetBottom,
            trailing: textInsetHorizontal,
        )
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

    // ColorOrGradientSetting is used for persistence, logging and comparison.
    public let chatColorSetting: ColorOrGradientSetting
    // ColorOrGradientValue is used for rendering.
    public let chatColorValue: ColorOrGradientValue

    public init(
        type: `Type`,
        thread: TSThread,
        viewWidth: CGFloat,
        hasWallpaper: Bool,
        shouldDimWallpaperInDarkMode: Bool,
        isWallpaperPhoto: Bool,
        chatColor: ColorOrGradientSetting,
        isStandaloneRenderItem: Bool = false,
    ) {
        self.type = type
        self.viewWidth = viewWidth
        self.isDarkThemeEnabled = Theme.isDarkThemeEnabled
        self.primaryTextColor = Theme.primaryTextColor
        self.hasWallpaper = hasWallpaper
        self.shouldDimWallpaperInDarkMode = shouldDimWallpaperInDarkMode
        self.isWallpaperPhoto = isWallpaperPhoto
        self.chatColorSetting = chatColor
        self.chatColorValue = chatColor.asValue

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

        self.isStandaloneRenderItem = isStandaloneRenderItem
    }

    // MARK: Colors

    /// - Returns: Bubble background color to be used for regular text messages and such.
    public func bubbleChatColor(isIncoming: Bool) -> ColorOrGradientValue {
        if isIncoming {
            bubbleChatColorIncoming
        } else {
            bubbleChatColorOutgoing
        }
    }

    private static func bubbleBackgroundBlurEffect(
        hasWallpaper: Bool,
        isDarkThemeEnabled: Bool,
        shouldDimWallpaperInDarkMode: Bool,
    ) -> UIVisualEffect? {
        guard hasWallpaper else { return nil }
        if isDarkThemeEnabled, shouldDimWallpaperInDarkMode {
            return UIBlurEffect(style: .systemUltraThinMaterial)
        }
        return UIBlurEffect(style: .systemThinMaterial)
    }

    /// - Returns: Background effect to be used for bubbles in chat if current chat environment requires one.
    /// If current chat does not require a blur effect `nil` will be returned.
    ///
    /// Defines the visual effect to be used in current theme and with the current chat wallpaper.
    /// Messages that could use this effect include, but are not limited to, incoming messages and system events.
    public var bubbleBackgroundBlurEffect: UIVisualEffect? {
        return Self.bubbleBackgroundBlurEffect(
            hasWallpaper: hasWallpaper,
            isDarkThemeEnabled: isDarkThemeEnabled,
            shouldDimWallpaperInDarkMode: shouldDimWallpaperInDarkMode,
        )
    }

    /// Contains logic for choosing background style to be used for incoming message bubbles.
    ///
    /// - Returns: Background style for incoming message bubbles when chat has provided parameters.
    /// - Parameter hasWallpaper: Pass `true` if chat has a wallpaper. Otherwise, pass `false`.
    /// - Parameter shouldDimWallpaperInDarkMode: Is only relevant if `hasWallpaper` is `true`.
    /// - Parameter isDarkThemeEnabled: Pass `true` to return style to be used in dark theme.
    public static func bubbleChatColorIncoming(
        hasWallpaper: Bool,
        shouldDimWallpaperInDarkMode: Bool,
        isDarkThemeEnabled: Bool,
    ) -> ColorOrGradientValue {
        if
            let blurEffect = bubbleBackgroundBlurEffect(
                hasWallpaper: hasWallpaper,
                isDarkThemeEnabled: isDarkThemeEnabled,
                shouldDimWallpaperInDarkMode: shouldDimWallpaperInDarkMode,
            )
        {
            return .blur(blurEffect: blurEffect)
        }
        let color = isDarkThemeEnabled ? UIColor(rgbHex: 0x2C2C2E) : UIColor(rgbHex: 0xE9E9E9)
        return .solidColor(color: color)
    }

    /// - Returns: Background style for incoming message bubble in the current chat.
    public var bubbleChatColorIncoming: ColorOrGradientValue {
        Self.bubbleChatColorIncoming(
            hasWallpaper: hasWallpaper,
            shouldDimWallpaperInDarkMode: shouldDimWallpaperInDarkMode,
            isDarkThemeEnabled: isDarkThemeEnabled,
        )
    }

    /// - Returns: Background style for outgoing message bubble in the current chat.
    public var bubbleChatColorOutgoing: ColorOrGradientValue {
        chatColorValue
    }

    public static var bubbleTextColorIncoming: UIColor {
        return bubbleTextColorIncomingThemed.forCurrentTheme
    }

    public static var bubbleTextColorIncomingThemed: ThemedColor {
        ThemedColor(light: Theme.lightThemePrimaryColor, dark: Theme.darkThemePrimaryColor)
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
        isDarkThemeEnabled ? Theme.darkThemeSecondaryTextAndIconColor : Theme.lightThemeSecondaryTextAndIconColor
    }

    public var bubbleTextColorOutgoing: UIColor {
        Self.bubbleTextColorOutgoingThemed.color(isDarkThemeEnabled: isDarkThemeEnabled)
    }

    public var bubbleSecondaryTextColorOutgoing: UIColor {
        isDarkThemeEnabled ? .ows_whiteAlpha60 : .ows_whiteAlpha80
    }

    public func bubbleTextColor(message: TSMessage) -> UIColor {
        if message.wasRemotelyDeleted, !hasWallpaper {
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

    /// - Returns: Stroke configuration to use on regular bubbles in chat for the theme provided.
    public static func bubbleStrokeConfiguration(isDarkThemeEnabled: Bool) -> BubbleStrokeConfiguration {
        let strokeColor = isDarkThemeEnabled ? UIColor(white: 1, alpha: 0.25) : UIColor(white: 0, alpha: 0.35)
        return BubbleStrokeConfiguration(color: strokeColor, width: 2 * CGFloat.hairlineWidth)
    }

    /// - Returns: Stroke configuration to use for incoming or outgoing message bubbles in chat.
    ///
    /// Unlike static method above this function will only return stroke configuration if bubbles must have one.
    public func bubbleStrokeConfiguration(isIncoming: Bool) -> BubbleStrokeConfiguration? {
        // Only use stroke for incoming messages and if there's a wallpaper.
        guard hasWallpaper, isIncoming else { return nil }

        return ConversationStyle.bubbleStrokeConfiguration(
            isDarkThemeEnabled: isDarkThemeEnabled,
        )
    }

    // Same across all themes
    public static var searchMatchHighlightColor: UIColor {
        return UIColor.yellow
    }
}

extension ConversationStyle: Equatable {
    public static func ==(lhs: ConversationStyle, rhs: ConversationStyle) -> Bool {
        // We need to compare any state that could affect
        // how we render view appearance.
        lhs.type.isValid == rhs.type.isValid &&
            lhs.viewWidth == rhs.viewWidth &&
            lhs.dynamicBodyTypePointSize == rhs.dynamicBodyTypePointSize &&
            lhs.isDarkThemeEnabled == rhs.isDarkThemeEnabled &&
            lhs.hasWallpaper == rhs.hasWallpaper &&
            lhs.shouldDimWallpaperInDarkMode == rhs.shouldDimWallpaperInDarkMode &&
            lhs.isWallpaperPhoto == rhs.isWallpaperPhoto &&
            lhs.maxMessageWidth == rhs.maxMessageWidth &&
            lhs.maxMediaMessageWidth == rhs.maxMediaMessageWidth &&
            lhs.textInsets == rhs.textInsets &&
            lhs.gutterLeading == rhs.gutterLeading &&
            lhs.gutterTrailing == rhs.gutterTrailing &&
            lhs.fullWidthGutterLeading == rhs.fullWidthGutterLeading &&
            lhs.fullWidthGutterTrailing == rhs.fullWidthGutterTrailing &&
            lhs.textInsets == rhs.textInsets &&
            lhs.lastTextLineAxis == rhs.lastTextLineAxis &&
            lhs.chatColorSetting == rhs.chatColorSetting
    }
}

extension ConversationStyle: CustomDebugStringConvertible {
    public var debugDescription: String {
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
            "chatColor: \(chatColorSetting), " +
            "]"
    }
}

extension ConversationStyle {
    public func quotedReplyHighlightColor() -> UIColor {
        UIColor(rgbHex: 0xB5B5B5)
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
