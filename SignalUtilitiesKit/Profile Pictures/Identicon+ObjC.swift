// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUtilitiesKit

@objc(LKIdenticon)
public final class Identicon: NSObject {
    
    @objc public static func generatePlaceholderIcon(seed: String, text: String, size: CGFloat) -> UIImage {
        let icon = PlaceholderIcon(seed: seed)
        
        var content = text

        if content.count > 2 && SessionId.Prefix(from: content) != nil {
            content.removeFirst(2)
        }
        
        let initials: String = content
            .split(separator: " ")
            .compactMap { word in word.first.map { String($0) } }
            .joined()
        let layer = icon.generateLayer(
            with: size,
            text: (initials.count >= 2 ?
                initials.substring(to: 2).uppercased() :
                content.substring(to: 2).uppercased()
            )
        )
        
        let rect = CGRect(origin: CGPoint.zero, size: layer.frame.size)
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        
        return renderer.image { layer.render(in: $0.cgContext) }
    }
}
