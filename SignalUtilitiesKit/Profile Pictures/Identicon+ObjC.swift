// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionUtilitiesKit

@objc(LKIdenticon)
public final class Identicon: NSObject {
    private static let placeholderCache: Atomic<NSCache<NSString, UIImage>> = {
        let result = NSCache<NSString, UIImage>()
        result.countLimit = 50
        
        return Atomic(result)
    }()
    
    @objc public static func generatePlaceholderIcon(seed: String, text: String, size: CGFloat) -> UIImage {
        let icon = PlaceholderIcon(seed: seed)
        
        var content: String = (text.hasSuffix("\(String(seed.suffix(4))))") ?
            (text.split(separator: "(")
                .first
                .map { String($0) })
                .defaulting(to: text) :
                text
        )

        if content.count > 2 && SessionId.Prefix(from: content) != nil {
            content.removeFirst(2)
        }
        
        let initials: String = content
            .split(separator: " ")
            .compactMap { word in word.first.map { String($0) } }
            .joined()
        let cacheKey: String = "\(content)-\(Int(floor(size)))"
        
        if let cachedIcon: UIImage = placeholderCache.wrappedValue.object(forKey: cacheKey as NSString) {
            return cachedIcon
        }
        
        let layer = icon.generateLayer(
            with: size,
            text: (initials.count >= 2 ?
                initials.substring(to: 2).uppercased() :
                content.substring(to: 2).uppercased()
            )
        )
        
        let rect = CGRect(origin: CGPoint.zero, size: layer.frame.size)
        let renderer = UIGraphicsImageRenderer(size: rect.size)
        let result = renderer.image { layer.render(in: $0.cgContext) }
        
        placeholderCache.mutate { $0.setObject(result, forKey: cacheKey as NSString) }
        
        return result
    }
}
