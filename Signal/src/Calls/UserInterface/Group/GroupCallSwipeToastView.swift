//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI

class GroupCallSwipeToastView: UIView {

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.setTemplateImageName("arrow-up-20", tintColor: .ows_white)
        view.autoSetDimensions(to: .square(20))
        return view
    }()

    private let label: UILabel = {
        let label = UILabel()
        label.font = UIFont.ows_dynamicTypeBody2
        label.textColor = .ows_gray05
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setCompressionResistanceHigh()
        return label
    }()

    var text: String? {
        get { label.text }
        set { label.text = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 8
        clipsToBounds = true
        isUserInteractionEnabled = false

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        addSubview(blurView)

        let stackView = UIStackView(arrangedSubviews: [
            imageView,
            label
        ])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8
        addSubview(stackView)

        blurView.autoPinEdgesToSuperviewEdges()
        stackView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
