//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

class SendMediaBottomButton: UIView {
    let button: OWSButton
    let blurView: UIVisualEffectView

    init(imageName: String, tintColor: UIColor, diameter: CGFloat, block: @escaping () -> Void) {
        self.button = OWSButton(imageName: imageName, tintColor: tintColor, block: block)
        button.imageEdgeInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

        let blurEffect = UIBlurEffect(style: .dark)
        self.blurView = UIVisualEffectView(effect: blurEffect)

        super.init(frame: .zero)

        layer.cornerRadius = diameter / 2
        blurView.layer.cornerRadius = diameter / 2
        blurView.clipsToBounds = true

        addSubview(blurView)
        blurView.autoPinEdgesToSuperviewEdges()

        let vibrancyEffect = UIVibrancyEffect(blurEffect: blurEffect)
        let vibrancyView = UIVisualEffectView(effect: vibrancyEffect)
        blurView.contentView.addSubview(vibrancyView)
        vibrancyView.autoPinEdgesToSuperviewEdges()

        addSubview(button)
        button.autoSetDimensions(to: CGSize(width: diameter, height: diameter))
        button.autoPinEdgesToSuperviewEdges()
        updateViewState()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var isSelected: Bool = false {
        didSet {
            updateViewState()
        }
    }

    func updateViewState() {
        if isSelected {
            button.tintColor = .ows_black
            blurView.isHidden = true
            backgroundColor = .ows_white
            setShadow()
        } else {
            button.tintColor = .ows_white
            blurView.isHidden = false
            backgroundColor = .clear
            layer.shadowRadius = 0
        }
    }
}
