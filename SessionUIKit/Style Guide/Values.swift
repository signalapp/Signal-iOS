import UIKit

@objc(LKValues)
public final class Values : NSObject {
    
    // MARK: - Alpha Values
    @objc public static let veryLowOpacity = CGFloat(0.12)
    @objc public static let lowOpacity = CGFloat(0.4)
    @objc public static let mediumOpacity = CGFloat(0.6)
    @objc public static let highOpacity = CGFloat(0.75)
    
    // MARK: - Font Sizes
    @objc public static let verySmallFontSize = isIPhone5OrSmaller ? CGFloat(10) : CGFloat(12)
    @objc public static let smallFontSize = isIPhone5OrSmaller ? CGFloat(13) : CGFloat(15)
    @objc public static let mediumFontSize = isIPhone5OrSmaller ? CGFloat(15) : CGFloat(17)
    @objc public static let largeFontSize = isIPhone5OrSmaller ? CGFloat(20) : CGFloat(22)
    @objc public static let veryLargeFontSize = isIPhone5OrSmaller ? CGFloat(24) : CGFloat(26)
    @objc public static let massiveFontSize = CGFloat(50)
    
    // MARK: - Element Sizes
    @objc public static let smallButtonHeight = isIPhone5OrSmaller ? CGFloat(24) : CGFloat(28)
    @objc public static let mediumButtonHeight = isIPhone5OrSmaller ? CGFloat(30) : CGFloat(34)
    @objc public static let largeButtonHeight = isIPhone5OrSmaller ? CGFloat(40) : CGFloat(45)
    @objc public static let alertButtonHeight: CGFloat = 50
    
    @objc public static let accentLineThickness = CGFloat(4)
    
    @objc public static let verySmallProfilePictureSize = CGFloat(26)
    @objc public static let smallProfilePictureSize = CGFloat(33)
    @objc public static let mediumProfilePictureSize = CGFloat(45)
    @objc public static let largeProfilePictureSize = CGFloat(75)
    
    @objc public static let searchBarHeight = CGFloat(36)

    @objc public static var separatorThickness: CGFloat { return 1 / UIScreen.main.scale }
    
    public static func footerGradientHeight(window: UIWindow?) -> CGFloat {
        return (
            Values.veryLargeSpacing +
            Values.largeButtonHeight +
            Values.smallSpacing +
            (window?.safeAreaInsets.bottom ?? 0)
        )
    }
    
    // MARK: - Distances
    @objc public static let verySmallSpacing = CGFloat(4)
    @objc public static let smallSpacing = CGFloat(8)
    @objc public static let mediumSpacing = CGFloat(16)
    @objc public static let largeSpacing = CGFloat(24)
    @objc public static let veryLargeSpacing = CGFloat(35)
    @objc public static let massiveSpacing = CGFloat(64)
    @objc public static let onboardingButtonBottomOffset = isIPhone5OrSmaller ? CGFloat(52) : CGFloat(72)
    
    // MARK: - iPad Sizes
    @objc public static let iPadModalWidth = UIScreen.main.bounds.width / 2
    @objc public static let iPadButtonWidth = CGFloat(196)
    @objc public static let iPadButtonSpacing = CGFloat(32)
    @objc public static let iPadUserSessionIdContainerWidth = iPadButtonWidth * 2 + iPadButtonSpacing
    @objc public static let iPadButtonContainerMargin = (UIScreen.main.bounds.width - iPadButtonSpacing) / 2 - iPadButtonWidth - largeSpacing
}
