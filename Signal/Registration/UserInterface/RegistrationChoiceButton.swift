//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI

class RegistrationChoiceButton: OWSFlatButton
{
    let titleLabel = UILabel()
    let bodyLabel = UILabel()
    let disclosureView = UILabel()

    init(
        title: String,
        body: String,
        iconName: String,
        iconSize: CGFloat? = nil
    ) {
        super.init()
        layer.cornerRadius = 8
        clipsToBounds = true

        // Icon

        let iconContainer = UIView()
        let iconView = UIImageView(image: UIImage(named: iconName))
        iconView.contentMode = .scaleAspectFit
        iconContainer.addSubview(iconView)
        iconContainer.autoSetDimensions(to: CGSize(square: 48))
        if let iconSize {
            iconView.autoCenterInSuperview()
            iconView.autoSetDimensions(to: .square(iconSize))
        } else {
            iconView.autoPinEdgesToSuperviewEdges()
        }

        // Labels

        titleLabel.text = title
        titleLabel.font = .dynamicTypeHeadline.semibold()
        titleLabel.textColor = UIColor.Signal.label
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping

        bodyLabel.text = body
        bodyLabel.font = .dynamicTypeFootnote
        bodyLabel.textColor = UIColor.Signal.secondaryLabel
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping

        let vStack = UIStackView(arrangedSubviews: [
            titleLabel,
            bodyLabel,
        ])
        vStack.axis = .vertical
        vStack.spacing = 2

        // Disclosure Indicator

        disclosureView.attributedText = SignalSymbol.chevronTrailing
            .attributedString(for: .body)
            .styled(with: .color(UIColor.Signal.tertiaryLabel))

        let hStack = UIStackView(arrangedSubviews: [
            iconContainer,
            vStack,
            UIView.hStretchingSpacer(),
            disclosureView,
        ])
        hStack.alignment = .center
        hStack.axis = .horizontal
        hStack.spacing = 12
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.layoutMargins = UIEdgeInsets(top: 21, leading: 12, bottom: 21, trailing: 16)
        hStack.isUserInteractionEnabled = false

        addSubview(hStack)
        hStack.autoPinEdgesToSuperviewEdges()

        themeDidChange()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        themeDidChange()
    }

    private func themeDidChange() {
        // Unfortunately, these don't update automatically because they're
        // being converted to images for UIButton's background API.
        setBackgroundColors(upColor: UIColor.Signal.quaternaryFill, downColor: UIColor.Signal.tertiaryFill)
    }
}
