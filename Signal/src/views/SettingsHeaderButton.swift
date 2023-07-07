//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

/// A button used in the header of a settings view.
class SettingsHeaderButton: OWSButton {

    var minimumWidth: CGFloat {
        label.width + 24
    }

    private let label: UILabel

    init(
        text: String,
        icon: ThemeIcon,
        backgroundColor: UIColor,
        isEnabled: Bool,
        block: (() -> Void)?
    ) {
        label = UILabel()

        if let block {
            super.init(block: block)
        } else {
            super.init()
        }

        dimsWhenHighlighted = true
        self.isEnabled = isEnabled
        layer.cornerRadius = 10
        setBackgroundImage(UIImage(color: backgroundColor), for: .normal)
        clipsToBounds = true
        accessibilityLabel = text

        let imageView = UIImageView()
        imageView.setTemplateImageName(Theme.iconName(icon), tintColor: Theme.primaryTextColor)
        imageView.autoSetDimension(.height, toSize: 24)
        imageView.contentMode = .scaleAspectFit

        addSubview(imageView)
        imageView.autoPinWidthToSuperview()
        imageView.autoPinEdge(toSuperviewEdge: .top, withInset: 8)

        label.font = .dynamicTypeCaption2Clamped
        label.textAlignment = .center
        label.text = text
        label.sizeToFit()
        label.setCompressionResistanceHorizontalHigh()

        addSubview(label)
        label.autoPinWidthToSuperview(withMargin: 12)
        label.autoPinEdge(toSuperviewEdge: .bottom, withInset: 6)
        label.autoPinEdge(.top, to: .bottom, of: imageView, withOffset: 2)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("Not implemented!")
    }
}
