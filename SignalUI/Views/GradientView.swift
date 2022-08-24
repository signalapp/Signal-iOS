//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

public class GradientView: UIView {

    public override class var layerClass: AnyClass { CAGradientLayer.self }

    public var gradientLayer: CAGradientLayer { layer as! CAGradientLayer }

    public var colors: [(color: UIColor, location: CGFloat)] {
        didSet {
            updateGradientLayer()
        }
    }

    public convenience init(from fromColor: UIColor, to toColor: UIColor) {
        self.init(colors: [
            (color: fromColor, location: 0),
            (color: toColor, location: 1)
        ])
    }

    public required init(colors: [(color: UIColor, location: CGFloat)]) {
        self.colors = colors
        super.init(frame: .zero)
        updateGradientLayer()
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateGradientLayer() {
        gradientLayer.colors = colors.map { $0.color.cgColor }
        gradientLayer.locations = colors.map { NSNumber(value: $0.location) }
    }

    /// Sets the `startPoint` and `endPoint` of the layer to reflect an angle in degrees
    /// where 0° starts at 12 o'clock and proceeds in a clockwise direction.
    func setAngle(_ angle: UInt32) {
        // While design provides gradients with 0° at 12 o'clock, core animation's
        // coordinate system works with 0° at 3 o'clock moving in a counter clockwise
        // direction. We need to convert the provided angle accordingly before
        // calculating the gradient's start and end points.

        let caAngle =
            (360 - angle) // Invert to counter clockwise direction
            + 90 // Rotate 90° counter clockwise to shift the start from 3 o'clock to 12 o'clock

        let radians = CGFloat(caAngle) * .pi / 180.0

        // (x,y) in terms of the signed unit circle
        var endPoint = CGPoint(x: cos(radians), y: sin(radians))

        // extrapolate to signed unit square
        if abs(endPoint.x) > abs(endPoint.y) {
            endPoint.x = endPoint.x > 0 ? 1 : -1
            endPoint.y = endPoint.x * tan(radians)
        } else {
            endPoint.y = endPoint.y > 0 ? 1 : -1
            endPoint.x = endPoint.y / tan(radians)
        }

        // The signed unit square is a coordinate space from:
        // (-1,-1) to (1,1), but the gradient coordinate space
        // ranges from (0,0) to (1,1) with 0 being the top
        // left. Convert each point accordingly to calculate
        // the final points.
        func convertPointToGradientSpace(_ point: CGPoint) -> CGPoint {
            return CGPoint(
                x: (point.x + 1) * 0.5,
                y: 1.0 - (point.y + 1) * 0.5
            )
        }

        // The start point will always be at the opposite side of the signed unit square.
        gradientLayer.startPoint = convertPointToGradientSpace(CGPoint(x: -endPoint.x, y: -endPoint.y))
        gradientLayer.endPoint = convertPointToGradientSpace(endPoint)
    }

}
