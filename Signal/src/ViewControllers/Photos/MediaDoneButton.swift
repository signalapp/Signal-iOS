//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import SignalUI
import UIKit

class MediaDoneButton: UIButton {

    var badgeNumber: Int = 0 {
        didSet {
            textLabel.text = numberFormatter.string(for: badgeNumber)
            invalidateIntrinsicContentSize()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private let numberFormatter: NumberFormatter = {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        return numberFormatter
    }()

    private let textLabel: UILabel = {
        let label = UILabel()
        label.textColor = .ows_white
        label.textAlignment = .center
        label.font = .ows_dynamicTypeSubheadline.ows_monospaced
        return label
    }()
    private var pillView: PillView!
    private var chevronImageView: UIImageView!
    private var dimmerView: UIView!

    private func commonInit() {
        pillView = PillView(frame: bounds)
        pillView.isUserInteractionEnabled = false
        pillView.layoutMargins = UIEdgeInsets(hMargin: 8, vMargin: 7)
        addSubview(pillView)
        pillView.autoPinEdgesToSuperviewEdges()

        let blurBackgroundView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        pillView.addSubview(blurBackgroundView)
        blurBackgroundView.autoPinEdgesToSuperviewEdges()

        let blueBadgeView = PillView(frame: bounds)
        blueBadgeView.backgroundColor = .ows_accentBlue
        blueBadgeView.layoutMargins = UIEdgeInsets(margin: 4)
        blueBadgeView.addSubview(textLabel)
        textLabel.autoPinEdgesToSuperviewMargins()

        let image: UIImage?
        if #available(iOS 13, *) {
            image = CurrentAppContext().isRTL ? UIImage(systemName: "chevron.backward") : UIImage(systemName: "chevron.right")
        } else {
            image = CurrentAppContext().isRTL ? UIImage(named: "chevron-left-20") : UIImage(named: "chevron-right-20")
        }
        chevronImageView = UIImageView(image: image!.withRenderingMode(.alwaysTemplate))
        chevronImageView.contentMode = .center
        chevronImageView.tintColor = .ows_white
        if #available(iOS 13, *) {
            chevronImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: textLabel.font.pointSize)
        }

        let hStack = UIStackView(arrangedSubviews: [blueBadgeView, chevronImageView])
        hStack.spacing = 6
        pillView.addSubview(hStack)
        hStack.autoPinEdgesToSuperviewMargins()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        guard traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory else {
            return
        }
        textLabel.font = .ows_dynamicTypeSubheadline.ows_monospaced
        if #available(iOS 13, *) {
            chevronImageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: textLabel.font.pointSize)
        }
    }

    override var isHighlighted: Bool {
        didSet {
            if isHighlighted {
                if dimmerView == nil {
                    dimmerView = UIView(frame: bounds)
                    dimmerView.isUserInteractionEnabled = false
                    dimmerView.backgroundColor = .ows_black
                    pillView.addSubview(dimmerView)
                    dimmerView.autoPinEdgesToSuperviewEdges()
                }
                dimmerView.alpha = 0.5
            } else if let dimmerView = dimmerView {
                dimmerView.alpha = 0
            }
        }
    }
}
