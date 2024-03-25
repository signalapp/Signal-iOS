//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

public class ConnectionsEducationSheetViewController: StackSheetViewController {
    public override var stackViewInsets: UIEdgeInsets {
        .init(top: 24, left: 24, bottom: 32, right: 24)
    }

    public required init() {
        super.init()

        stackView.alignment = .fill
        stackView.spacing = 12

        stackView.addArrangedSubview(connectionsImageView)
        stackView.setCustomSpacing(24, after: connectionsImageView)
        stackView.addArrangedSubview(header)
        stackView.setCustomSpacing(20, after: header)
        let bulletPoints = bulletPoints
        stackView.addArrangedSubviews(bulletPoints)
        stackView.setCustomSpacing(20, after: bulletPoints.last!)
        stackView.addArrangedSubview(footer)
    }

    let connectionsImageView: UIImageView = {
        let view = UIImageView()
        view.image = UIImage(named: "connections-display-bold")
        view.tintColor = Theme.primaryTextColor
        view.contentMode = .scaleAspectFit
        view.autoSetDimension(.height, toSize: 56)
        return view
    }()

    let header: UILabel = {
        let label = UILabel()
        label.attributedText = OWSLocalizedString(
            "STORY_SETTINGS_LEARN_MORE_SHEET_HEADER_FORMAT",
            comment: "Header for the explainer sheet for signal connections"
        ).styled(
            with: .font(.dynamicTypeBody),
            .xmlRules([.style("bold", .init(.font(UIFont.dynamicTypeBody.semibold())))])
        )
        label.textColor = Theme.primaryTextColor
        label.numberOfLines = 0
        label.setCompressionResistanceHigh()
        return label
    }()

    let bulletPoints: [UIView] = {
        return [
            OWSLocalizedString(
                "STORY_SETTINGS_LEARN_MORE_SHEET_BULLET_1",
                comment: "First bullet point for the explainer sheet for signal connections"
            ),
            OWSLocalizedString(
                "STORY_SETTINGS_LEARN_MORE_SHEET_BULLET_2",
                comment: "Second bullet point for the explainer sheet for signal connections"
            ),
            OWSLocalizedString(
                "STORY_SETTINGS_LEARN_MORE_SHEET_BULLET_3",
                comment: "Third bullet point for the explainer sheet for signal connections"
            )
        ].map { text in
            return ListPointView(text: text)
        }
    }()

    let footer: UILabel = {
        let label = UILabel()
        label.text = OWSLocalizedString(
            "STORY_SETTINGS_LEARN_MORE_SHEET_FOOTER",
            comment: "Footer for the explainer sheet for signal connections"
        )
        label.textColor = Theme.primaryTextColor
        label.font = .dynamicTypeBody
        label.numberOfLines = 0
        label.setCompressionResistanceHigh()
        return label
    }()

    private class ListPointView: UIStackView {

        init(text: String) {
            super.init(frame: .zero)

            self.axis = .horizontal
            self.alignment = .center
            self.spacing = 8

            let label = UILabel()
            label.text = text
            label.numberOfLines = 0
            label.textColor = Theme.primaryTextColor
            label.font = .dynamicTypeBody

            let bulletPoint = UIView()
            bulletPoint.backgroundColor = UIColor(rgbHex: 0xC4C4C4)

            addArrangedSubview(.spacer(withWidth: 4))
            addArrangedSubview(bulletPoint)
            addArrangedSubview(label)

            bulletPoint.autoSetDimensions(to: .init(width: 4, height: 14))
            label.setCompressionResistanceHigh()
        }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
