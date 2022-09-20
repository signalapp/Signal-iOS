// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

extension UINavigationBar {
    func generateSnapshot(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        let scale = UIScreen.main.scale
        
        guard let navBarSuperview: UIView = superview else { return nil }
        
        UIGraphicsBeginImageContextWithOptions(layer.frame.size, false, scale)
        
        guard let context: CGContext = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        
        layer.render(in: context)
        
        guard let image: UIImage = UIGraphicsGetImageFromCurrentImageContext() else {
            UIGraphicsEndImageContext()
            return nil
        }
        UIGraphicsEndImageContext()
        
        let snapshotView: UIView = UIView(
            frame: CGRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: frame.maxY
            )
        )
        snapshotView.themeBackgroundColorForced = self.themeBackgroundColorForced
        
        let imageView: UIImageView = UIImageView(image: image)
        imageView.frame = frame
        snapshotView.addSubview(imageView)
        
        let presentationFrame = coordinateSpace.convert(snapshotView.frame, from: navBarSuperview)
        
        return (snapshotView, presentationFrame)
    }
}
