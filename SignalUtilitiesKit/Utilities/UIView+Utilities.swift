import SessionUIKit

public extension UIView {

    static func hSpacer(_ width: CGFloat) -> UIView {
        let result = UIView()
        result.set(.width, to: width)
        return result
    }

    static func vSpacer(_ height: CGFloat) -> UIView {
        let result = UIView()
        result.set(.height, to: height)
        return result
    }
    
    static func vhSpacer(_ width: CGFloat, _ height: CGFloat) -> UIView {
        let result = UIView()
        result.set(.width, to: width)
        result.set(.height, to: height)
        return result
    }

    static func separator() -> UIView {
        let result = UIView()
        result.set(.height, to: Values.separatorThickness)
        result.backgroundColor = Colors.separator
        return result
    }
}
