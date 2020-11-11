
extension UIImage {
    
    func scaled(to size: CGSize) -> UIImage {
        var rect = CGRect.zero
        let aspectRatio = min(size.width / self.size.width, size.height / self.size.height)
        rect.size.width = self.size.width * aspectRatio
        rect.size.height = self.size.height * aspectRatio
        rect.origin.x = (size.width - rect.size.width) / 2
        rect.origin.y = (size.height - rect.size.height) / 2
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        draw(in: rect)
        let result = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return result
    }
}
