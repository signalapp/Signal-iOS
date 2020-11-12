import UIKit

@objc(LKFonts)
public final class Fonts : NSObject {
    
    @objc public static func spaceMono(ofSize size: CGFloat) -> UIFont {
        return UIFont(name: "SpaceMono-Regular", size: size)!
    }
    
    @objc public static func boldSpaceMono(ofSize size: CGFloat) -> UIFont {
        return UIFont(name: "SpaceMono-Bold", size: size)!
    }
}
