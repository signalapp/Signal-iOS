// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit.UIColor
import SessionUtilitiesKit

public extension Theme {
    enum PrimaryColor: String, Codable, CaseIterable, EnumStringSetting {
        case green
        case blue
        case purple
        case pink
        case red
        case orange
        case yellow
        
        internal init?(color: UIColor?) {
            guard
                let color: UIColor = color,
                let primaryColor: PrimaryColor = PrimaryColor.allCases.first(where: { $0.color == color })
            else { return nil }
            
            self = primaryColor
        }
        
        public var color: UIColor {
            switch self {
                case .green: return #colorLiteral(red: 0.1921568627, green: 0.9450980392, blue: 0.5882352941, alpha: 1)
                case .blue: return #colorLiteral(red: 0.3411764706, green: 0.7882352941, blue: 0.9803921569, alpha: 1)
                case .purple: return #colorLiteral(red: 0.7882352941, green: 0.5764705882, blue: 1, alpha: 1)
                case .pink: return #colorLiteral(red: 1, green: 0.5843137255, blue: 0.937254902, alpha: 1)
                case .red: return #colorLiteral(red: 1, green: 0.6117647059, blue: 0.5568627451, alpha: 1)
                case .orange: return #colorLiteral(red: 0.9882352941, green: 0.6941176471, blue: 0.3490196078, alpha: 1)
                case .yellow: return #colorLiteral(red: 0.9803921569, green: 0.8392156863, blue: 0.3411764706, alpha: 1)
            }
        }
    }
}

public extension UIColor {
    static let primary: UIColor = UIColor(dynamicProvider: { _ in
        return ThemeManager.primaryColor.color
    })
}
