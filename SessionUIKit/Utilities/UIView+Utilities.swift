// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

public extension UIView {
    func toImage(isOpaque: Bool, scale: CGFloat) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = isOpaque
        
        let renderer = UIGraphicsImageRenderer(bounds: self.bounds, format: format)
        
        return renderer.image { context in
            self.layer.render(in: context.cgContext)
        }
    }
    
    class func spacer(withWidth width: CGFloat) -> UIView {
        let view = UIView()
        view.autoSetDimension(.width, toSize: width)
        return view
    }

    class func spacer(withHeight height: CGFloat) -> UIView {
        let view = UIView()
        view.autoSetDimension(.height, toSize: height)
        return view
    }

    class func hStretchingSpacer() -> UIView {
        let view = UIView()
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(UILayoutPriority(0), for: .horizontal)
        
        return view
    }

    class func vStretchingSpacer() -> UIView {
        let view = UIView()
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(UILayoutPriority(0), for: .vertical)
        
        return view
    }
    
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
