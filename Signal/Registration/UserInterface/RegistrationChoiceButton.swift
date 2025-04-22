//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI

class RegistrationChoiceButton: OWSFlatButton
{
    let titleLabel: UILabel
    let bodyLabel: UILabel
    let disclosureView: UIImageView
    init(
        title: String,
        body: String,
        iconName: String
    ) {
        titleLabel = UILabel()
        bodyLabel = UILabel()
        disclosureView = UIImageView()
        super.init()
        layer.cornerRadius = 8
        clipsToBounds = true

        // Icon

        let iconContainer = UIView()
        let iconView = UIImageView(image: UIImage(named: iconName))
        iconView.contentMode = .scaleAspectFit
        iconContainer.addSubview(iconView)
        iconView.autoPinWidthToSuperview()
        iconView.autoSetDimensions(to: CGSize(square: 48))
        iconView.autoVCenterInSuperview()
        iconView.autoMatch(.height, to: .height, of: iconContainer, withOffset: 0, relation: .lessThanOrEqual)

        // Labels

        titleLabel.text = title
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping

        bodyLabel.text = body
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping

        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()

        let vStack = UIStackView(arrangedSubviews: [
            topSpacer,
            titleLabel,
            bodyLabel,
            bottomSpacer
        ])
        vStack.axis = .vertical
        vStack.spacing = 8

        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)

        // Disclosure Indicator

        let disclosureContainer = UIView()
        disclosureView.setTemplateImage(
            UIImage(imageLiteralResourceName: "chevron-right-20"),
            tintColor: Theme.secondaryTextAndIconColor
        )
        disclosureView.contentMode = .scaleAspectFit
        disclosureContainer.addSubview(disclosureView)
        disclosureView.autoPinEdgesToSuperviewEdges()
        disclosureView.autoSetDimension(.width, toSize: 20)

        let hStack = UIStackView(arrangedSubviews: [
            iconContainer,
            vStack,
            disclosureContainer
        ])
        hStack.axis = .horizontal
        hStack.spacing = 16
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.layoutMargins = UIEdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16)
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
        setBackgroundColors(upColor: Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_gray02)
        titleLabel.font = .dynamicTypeBody.semibold()
        titleLabel.textColor = Theme.primaryTextColor
        bodyLabel.font = .dynamicTypeBody2
        bodyLabel.textColor = Theme.secondaryTextAndIconColor
        disclosureView.tintColor = Theme.secondaryTextAndIconColor
    }
}
