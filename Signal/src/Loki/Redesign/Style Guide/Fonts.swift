
@objc(LKFonts)
final class Fonts : NSObject {
    
    @objc static func spaceMono(ofSize size: CGFloat) -> UIFont {
        return UIFont(name: "SpaceMono-Regular", size: size)!
    }
    
    @objc static func boldSpaceMono(ofSize size: CGFloat) -> UIFont {
        return UIFont(name: "SpaceMono-Bold", size: size)!
    }
}
