// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import SessionUIKit

public extension UIView {
    static func hSpacer(_ width: CGFloat) -> UIView {
        let result: UIView = UIView()
        result.set(.width, to: width)
        
        return result
    }

    static func vSpacer(_ height: CGFloat) -> UIView {
        let result: UIView = UIView()
        result.set(.height, to: height)
        
        return result
    }
    
    static func vhSpacer(_ width: CGFloat, _ height: CGFloat) -> UIView {
        let result: UIView = UIView()
        result.set(.width, to: width)
        result.set(.height, to: height)
        
        return result
    }

    static func separator() -> UIView {
        let result: UIView = UIView()
        result.set(.height, to: Values.separatorThickness)
        result.themeBackgroundColor = .borderSeparator
        
        return result
    }
}
