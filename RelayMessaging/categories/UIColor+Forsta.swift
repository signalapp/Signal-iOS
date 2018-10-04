//
//  UIColor+Forsta.swift
//  Pods-RelayMessaging
//
//  Created by Mark Descalzo on 9/10/18.
//

import UIKit

@objc
extension UIColor {
    
    public class func systemPrimaryButtonColor() -> UIColor? {
        var sharedColor: UIColor?
        var onceToken: Int = 0
        if (onceToken == 0) {
            sharedColor = UIView().tintColor
        }
        onceToken = 1
        return sharedColor
    }
    
    public class func FL_randomPopColor() -> UIColor {
        return self.FL_popColors()[ Int(arc4random_uniform(UInt32(self.FL_popColors().count )))]
    }
    
    public class func FL_popColors() -> Array<UIColor> {
        return [ UIColor.FL_darkGreen(),
                 UIColor.FL_mediumDarkGreen(),
                 UIColor.FL_mediumGreen(),
                 UIColor.FL_mediumLightGreen(),
                 UIColor.FL_lightGreen(),
                 UIColor.FL_darkRed(),
                 UIColor.FL_mediumDarkRed(),
                 UIColor.FL_mediumRed(),
                 UIColor.FL_mediumLightRed(),
                 UIColor.FL_lightRed(),
                 UIColor.FL_darkBlue1(),
                 UIColor.FL_mediumDarkBlue1(),
                 UIColor.FL_mediumBlue1(),
                 UIColor.FL_mediumLightBlue1(),
                 UIColor.FL_lightBlue1(),
                 UIColor.FL_darkBlue2(),
                 UIColor.FL_mediumDarkBlue2(),
                 UIColor.FL_mediumBlue2(),
                 UIColor.FL_mediumLightBlue2(),
                 UIColor.FL_lightBlue2(),
                 UIColor.FL_lightYellow(),
                 UIColor.FL_mediumLightYellow(),
                 UIColor.FL_mediumYellow(),
                 UIColor.FL_darkYellow(),
        ]
    }
    
    public class func FL_incomingBubbleColors() -> Dictionary<String, UIColor> {
        return [ "Gray": UIColor.FL_lightGray(),
                "Orange": UIColor.FL_lightRed(),
                "Lime": UIColor.FL_lightGreen(),
                "Mist": UIColor.FL_lightBlue1(),
                "Blue": UIColor.FL_lightBlue2(),
                "Lavender": UIColor.FL_lightPurple(),
                "Pink": UIColor.FL_lightPink(),
                "Gold": UIColor.FL_lightYellow() ]
    }
    
    public class func FL_outgoingBubbleColors() -> Dictionary<String, UIColor> {
        return [ "Black": UIColor.black,
                "Brick": UIColor.FL_darkRed(),
                "Green": UIColor.FL_darkGreen(),
                "Blue": UIColor.FL_darkBlue1(),
                "Midnight": UIColor.FL_darkBlue2(),
                "Purple": UIColor.FL_mediumPurple(),
                "Pink": UIColor.FL_mediumPink(),
                "Gold": UIColor.FL_mediumYellow() ]
    }
    
    public class func FL_lightGray() -> UIColor {
        return UIColor.color(hex: "#CACACA")
    }
    
    public class func FL_mediumGray() -> UIColor {
        return UIColor.color(hex: "#9F9F9F")
    }
    
    public class func FL_darkGray() -> UIColor {
        return UIColor.color(hex: "#616161")
    }
    
    public class func FL_darkestGray() -> UIColor {
        return UIColor.color(hex: "#4B4B4B")
    }
    
    public class func FL_darkGreen() -> UIColor {
        return UIColor.color(hex: "#919904")
    }
    
    public class func FL_mediumDarkGreen() -> UIColor {
        return UIColor.color(hex: "#90B718")
    }
    
    public class func FL_mediumGreen() -> UIColor {
        return UIColor.color(hex: "#AFD23F")
    }
    
    public class func FL_mediumLightGreen() -> UIColor {
        return UIColor.color(hex: "#BED868")
    }
    
    public class func FL_lightGreen() -> UIColor {
        return UIColor.color(hex: "#DEEF95")
    }
    
    public class func FL_darkRed() -> UIColor {
        return UIColor.color(hex: "#9A4422")
    }
    
    public class func FL_mediumDarkRed() -> UIColor {
        return UIColor.color(hex: "#BE5D28")
    }
    
    public class func FL_mediumRed() -> UIColor {
        return UIColor.color(hex: "#F46D20")
    }
    
    public class func FL_mediumLightRed() -> UIColor {
        return UIColor.color(hex: "#F69348")
    }
    
    public class func FL_lightRed() -> UIColor {
        return UIColor.color(hex: "#FDC79E")
    }
    
    public class func FL_darkBlue1() -> UIColor {
        return UIColor.color(hex: "#124b63")
    }
    
    public class func FL_mediumDarkBlue1() -> UIColor {
        return UIColor.color(hex: "#0a76af")
    }
    
    public class func FL_mediumBlue1() -> UIColor {
        return UIColor.color(hex: "#2bace2")
    }
    
    public class func FL_mediumLightBlue1() -> UIColor {
        return UIColor.color(hex: "#6abde9")
    }
    
    public class func FL_lightBlue1() -> UIColor {
        return UIColor.color(hex: "#9ccce0")
    }
    
    public class func FL_darkBlue2() -> UIColor {
        return UIColor.color(hex: "#0a76af")
    }
    
    public class func FL_mediumDarkBlue2() -> UIColor {
        return UIColor.color(hex: "#6abde9")
    }
    
    public class func FL_mediumBlue2() -> UIColor {
        return UIColor.color(hex: "#80ceff")
    }
    
    public class func FL_mediumLightBlue2() -> UIColor {
        return UIColor.color(hex: "#c5e0ef")
    }
    
    public class func FL_lightBlue2() -> UIColor {
        return UIColor.color(hex: "#d7e6f5")
    }
    
    public class func FL_lightPurple() -> UIColor {
        return UIColor.color(hex: "#ccc3e5")
    }
    
    public class func FL_mediumPurple() -> UIColor {
        return UIColor.color(hex: "#5e37c4")
    }
    
    public class func FL_lightYellow() -> UIColor {
        return UIColor.color(hex: "#ffe5b2")
    }
    
    public class func FL_mediumLightYellow() -> UIColor {
        return UIColor.color(hex: "#e9bf6a")
    }
    
    public class func FL_mediumYellow() -> UIColor {
        return UIColor.color(hex: "#ffbb37")
    }
    
    public class func FL_darkYellow() -> UIColor {
        return UIColor.color(hex: "#634812")
    }
    
    public class func FL_lightPink() -> UIColor {
        return UIColor.color(hex: "#e2c0d4")
    }
    
    public class func FL_mediumPink() -> UIColor {
        return UIColor.color(hex: "#e32d94")
    }

    
    // Source: https://cocoacasts.com/from-hex-to-uicolor-and-back-in-swift/
    // MARK: - Initialization
    public class func color(hex: String) -> UIColor {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt32 = 0
        
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0
        
        let length = hexSanitized.count
        
        guard Scanner(string: hexSanitized).scanHexInt32(&rgb) else {
            #if DEBUG
            return UIColor.magenta
            #else
            return UIColor.gray
            #endif
        }
        
        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0
            
        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
            
        } else {
            #if DEBUG
            return UIColor.magenta
            #else
            return UIColor.gray
            #endif
        }
        
        return UIColor.init(red: r, green: g, blue: b, alpha: a)
    }
    
    // MARK: - Computed Properties
    var toHex: String? {
        return toHex()
    }
    
    // MARK: - From UIColor to String
    func toHex(alpha: Bool = false) -> String? {
        guard let components = cgColor.components, components.count >= 3 else {
            return nil
        }
        
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)
        
        if components.count >= 4 {
            a = Float(components[3])
        }
        
        if alpha {
            return String(format: "%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }
    
}
