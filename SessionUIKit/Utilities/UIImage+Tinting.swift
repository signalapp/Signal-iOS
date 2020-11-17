import UIKit

public extension UIImage {

    func withTint(_ color: UIColor) -> UIImage? {
        let template = self.withRenderingMode(.alwaysTemplate)
        let imageView = UIImageView(image: template)
        imageView.tintColor = color
        return imageView.toImage(isOpaque: imageView.isOpaque, scale: UIScreen.main.scale)
    }
}
