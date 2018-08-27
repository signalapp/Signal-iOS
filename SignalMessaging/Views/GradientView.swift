//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

public class GradientView: UIView {

    let gradientLayer = CAGradientLayer()

    public required init(from fromColor: UIColor, to toColor: UIColor) {
        gradientLayer.colors = [fromColor.cgColor, toColor.cgColor]
        super.init(frame: CGRect.zero)

        self.layer.addSublayer(gradientLayer)
    }

    public required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = self.bounds
    }
}
