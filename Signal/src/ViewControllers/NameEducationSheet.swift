//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class NameEducationSheet: StackSheetViewController {
    override var stackViewInsets: UIEdgeInsets {
        .init(top: 24, left: 24, bottom: 32, right: 24)
    }

    override var sheetBackgroundColor: UIColor {
        UIColor.Signal.secondaryBackground
    }

    override var handleBackgroundColor: UIColor {
        UIColor.Signal.transparentSeparator
    }

    private let type: SafetyTipsType

    init(type: SafetyTipsType) {
        self.type = type
        super.init()

        stackView.alignment = .fill
        stackView.spacing = 12

        stackView.addArrangedSubview(heroImageView)
        stackView.setCustomSpacing(24, after: heroImageView)
        stackView.addArrangedSubview(header)
        stackView.setCustomSpacing(20, after: header)
        let bulletPoints = self.bulletPoints.map { text in
            ListPointView(text: text)
        }
        stackView.addArrangedSubviews(bulletPoints)
        stackView.setCustomSpacing(20, after: bulletPoints.last!)
    }

    private lazy var heroImageView: UIImageView = {
        let view = UIImageView()
        view.image = switch self.type {
        case .contact:
            UIImage(named: "person-questionmark-display")
        case .group:
            UIImage(named: "group-questionmark-display")
        }
        view.tintColor = .label
        view.contentMode = .scaleAspectFit
        view.autoSetDimension(.height, toSize: 56)
        return view
    }()

    private lazy var header: UILabel = {
        let label = UILabel()
        let text = switch self.type {
        case .contact:
            OWSLocalizedString(
                "PROFILE_NAME_EDUCATION_SHEET_HEADER_FORMAT",
                comment: "Header for the explainer sheet for profile names",
            )
        case .group:
            OWSLocalizedString(
                "GROUP_NAME_EDUCATION_SHEET_HEADER_FORMAT",
                comment: "Header for the explainer sheet for group names",
            )
        }
        label.attributedText = text.styled(
            with: .font(.dynamicTypeBody),
            .xmlRules([.style("bold", .init(.font(UIFont.dynamicTypeHeadline)))]),
        )
        label.textColor = .label
        label.numberOfLines = 0
        label.setCompressionResistanceHigh()
        return label
    }()

    private var bulletPoints: [String] {
        switch self.type {
        case .contact:
            [
                OWSLocalizedString(
                    "PROFILE_NAME_EDUCATION_SHEET_BULLET_1",
                    comment: "First bullet point for the explainer sheet for profile names",
                ),
                OWSLocalizedString(
                    "PROFILE_NAME_EDUCATION_SHEET_BULLET_2",
                    comment: "Second bullet point for the explainer sheet for profile names",
                ),
                OWSLocalizedString(
                    "PROFILE_NAME_EDUCATION_SHEET_BULLET_3",
                    comment: "Third bullet point for the explainer sheet for profile names",
                ),
            ]
        case .group:
            [
                OWSLocalizedString(
                    "GROUP_NAME_EDUCATION_SHEET_BULLET_1",
                    comment: "First bullet point for the explainer sheet for group names",
                ),
                OWSLocalizedString(
                    "GROUP_NAME_EDUCATION_SHEET_BULLET_2",
                    comment: "Second bullet point for the explainer sheet for group names",
                ),
                OWSLocalizedString(
                    "GROUP_NAME_EDUCATION_SHEET_BULLET_3",
                    comment: "Third bullet point for the explainer sheet for group names",
                ),
            ]
        }
    }

    private class ListPointView: UIStackView {
        init(text: String) {
            super.init(frame: .zero)

            self.axis = .horizontal
            self.alignment = .center
            self.spacing = 8

            let label = UILabel()
            label.text = text
            label.numberOfLines = 0
            label.textColor = .label
            label.font = .dynamicTypeBody

            let bulletPoint = UIView()
            bulletPoint.backgroundColor = UIColor.Signal.tertiaryLabel

            addArrangedSubview(.spacer(withWidth: 4))
            addArrangedSubview(bulletPoint)
            addArrangedSubview(label)

            bulletPoint.autoSetDimension(.width, toSize: 4)
            bulletPoint.autoPinHeightToSuperview(withMargin: 4)
            bulletPoint.layer.cornerRadius = 2
            label.setCompressionResistanceHigh()
        }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

#if DEBUG
@available(iOS 17, *)
#Preview("Profile names") {
    SheetPreviewViewController(sheet: NameEducationSheet(type: .contact))
}

@available(iOS 17, *)
#Preview("Group names") {
    SheetPreviewViewController(sheet: NameEducationSheet(type: .group))
}
#endif
