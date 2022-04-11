//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

public class GradientView: UIView {

    public let gradientLayer = CAGradientLayer()
    public var colors: [(color: UIColor, location: Double)] {
        didSet {
            updateColors()
        }
    }

    public convenience init(from fromColor: UIColor, to toColor: UIColor) {
        self.init(colors: [
            (color: fromColor, location: 0),
            (color: toColor, location: 1)
        ])
    }

    public required init(colors: [(color: UIColor, location: Double)]) {
        self.colors = colors
        super.init(frame: .zero)
        updateColors()
        layer.addSublayer(gradientLayer)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = self.bounds
    }

    private func updateColors() {
        gradientLayer.colors = colors.map { $0.color.cgColor }
        gradientLayer.locations = colors.map { NSNumber(value: $0.location) }
    }
}
