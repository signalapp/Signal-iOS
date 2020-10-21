
@objc(LKValues)
public final class Values : NSObject {
    
    // MARK: - Alpha Values
    @objc public static let unimportantElementOpacity = CGFloat(0.6)
    @objc public static let conversationCellTimestampOpacity = CGFloat(0.4)
    @objc public static let textFieldBorderOpacity = CGFloat(0.4)
    @objc public static let modalBackgroundOpacity = CGFloat(0.75)
    @objc public static let composeViewTextFieldBorderOpacity = CGFloat(0.12)
    @objc public static let composeViewTextFieldPlaceholderOpacity = CGFloat(0.4)
    
    // MARK: - Font Sizes
    @objc public static let verySmallFontSize = isIPhone5OrSmaller ? CGFloat(10) : CGFloat(12)
    @objc public static let smallFontSize = isIPhone5OrSmaller ? CGFloat(13) : CGFloat(15)
    @objc public static let mediumFontSize = isIPhone5OrSmaller ? CGFloat(15) : CGFloat(17)
    @objc public static let largeFontSize = isIPhone5OrSmaller ? CGFloat(20) : CGFloat(22)
    @objc public static let veryLargeFontSize = isIPhone5OrSmaller ? CGFloat(24) : CGFloat(26)
    @objc public static let massiveFontSize = CGFloat(50)
    
    // MARK: - Element Sizes
    @objc public static let smallButtonHeight = isIPhone5OrSmaller ? CGFloat(24) : CGFloat(27)
    @objc public static let mediumButtonHeight = isIPhone5OrSmaller ? CGFloat(30) : CGFloat(34)
    @objc public static let largeButtonHeight = isIPhone5OrSmaller ? CGFloat(40) : CGFloat(45)
    @objc public static let accentLineThickness = CGFloat(4)
    @objc public static let verySmallProfilePictureSize = CGFloat(26)
    @objc public static let smallProfilePictureSize = CGFloat(35)
    @objc public static let mediumProfilePictureSize = CGFloat(45)
    @objc public static let largeProfilePictureSize = CGFloat(75)
    @objc public static let borderThickness = CGFloat(1)
    @objc public static let conversationCellStatusIndicatorSize = CGFloat(14)
    @objc public static let searchBarHeight = CGFloat(36)
    @objc public static let newConversationButtonCollapsedSize = CGFloat(60)
    @objc public static let newConversationButtonExpandedSize = CGFloat(72)
    @objc public static let textFieldHeight = isIPhone5OrSmaller ? CGFloat(48) : CGFloat(80)
    @objc public static let textFieldCornerRadius = CGFloat(8)
    @objc public static let separatorLabelHeight = CGFloat(24)
    @objc public static var separatorThickness: CGFloat { return 1 / UIScreen.main.scale }
    @objc public static let tabBarHeight = isIPhone5OrSmaller ? CGFloat(32) : CGFloat(48)
    @objc public static let settingButtonHeight = isIPhone5OrSmaller ? CGFloat(52) : CGFloat(75)
    @objc public static let modalCornerRadius = CGFloat(10)
    @objc public static let modalButtonCornerRadius = CGFloat(5)
    @objc public static let fakeChatBubbleWidth = CGFloat(224)
    @objc public static let fakeChatBubbleCornerRadius = CGFloat(10)
    @objc public static let fakeChatViewHeight = isIPhone5OrSmaller ? CGFloat(234) : CGFloat(260)
    @objc public static let composeViewTextFieldBorderThickness = 1 / UIScreen.main.scale
    @objc public static let messageBubbleCornerRadius: CGFloat = 10
    @objc public static let progressBarThickness: CGFloat = 2
    @objc public static let pnOptionCornerRadius = CGFloat(8)
    @objc public static let pathStatusViewSize = CGFloat(8)
    @objc public static var pathRowLineThickness: CGFloat { return 1 / UIScreen.main.scale }
    @objc public static let pathRowDotSize = CGFloat(8)
    @objc public static let pathRowExpandedDotSize = CGFloat(16)
    @objc public static let pathRowHeight = isIPhone5OrSmaller ? CGFloat(52) : CGFloat(75)
    
    // MARK: - Distances
    @objc public static let verySmallSpacing = CGFloat(4)
    @objc public static let smallSpacing = CGFloat(8)
    @objc public static let mediumSpacing = CGFloat(16)
    @objc public static let largeSpacing = CGFloat(24)
    @objc public static let veryLargeSpacing = CGFloat(35)
    @objc public static let massiveSpacing = CGFloat(64)
    @objc public static let newConversationButtonBottomOffset = CGFloat(52)
    @objc public static let onboardingButtonBottomOffset = isIPhone5OrSmaller ? CGFloat(52) : CGFloat(72)
    
    // MARK: - Animation Values
    @objc public static let fakeChatStartDelay: TimeInterval = 1
    @objc public static let fakeChatAnimationDuration: TimeInterval = 0.4
    @objc public static let fakeChatDelay: TimeInterval = 1.5
    @objc public static let fakeChatMessagePopAnimationStartScale: CGFloat = 0.6
}
