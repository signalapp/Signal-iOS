//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

public class GradientView: UIView {

    let gradientLayer = CAGradientLayer()

    public convenience init(from fromColor: UIColor, to toColor: UIColor) {
        self.init(colors: [
            (color: fromColor, location: 0),
            (color: toColor, location: 1)
        ])
    }

    public required init(colors: [(color: UIColor, location: Double)]) {
        gradientLayer.colors = colors.map { $0.color.cgColor }
        gradientLayer.locations = colors.map { NSNumber(value: $0.location) }

        super.init(frame: .zero)
        layer.addSublayer(gradientLayer)
    }

    public required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = self.bounds
    }
}
