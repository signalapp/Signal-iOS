
extension CGRect {

    init(center: CGPoint, size: CGSize) {
        let originX = center.x - size.width / 2
        let originY = center.y - size.height / 2
        let origin = CGPoint(x: originX, y: originY)
        self.init(origin: origin, size: size)
    }
}
