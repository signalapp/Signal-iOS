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

    private static let capsuleColor = UIColor.Signal.warningLabel
    private let type: SafetyTipsType

    init(type: SafetyTipsType) {
        self.type = type
        super.init()

        stackView.alignment = .fill
        stackView.spacing = 12

        stackView.addArrangedSubview(heroImageContainerView)
        stackView.setCustomSpacing(24, after: heroImageContainerView)
        stackView.addArrangedSubview(header)
        stackView.setCustomSpacing(20, after: header)
        let bulletPoints = self.bulletPoints.map { text in
            BulletPointView(text: text)
        }
        stackView.addArrangedSubviews(bulletPoints)
        stackView.setCustomSpacing(20, after: bulletPoints.last!)
    }

    private lazy var heroImageContainerView: UIView = {
        let imageView = UIImageView()
        imageView.image = switch self.type {
        case .contact:
            .personQuestionmarkCompact
        case .group:
            .groupQuestionmarkCompact
        }
        imageView.tintColor = Self.capsuleColor
        imageView.contentMode = .scaleAspectFit

        let imageInnerContainer = UIView()
        imageInnerContainer.backgroundColor = Self.capsuleColor.withAlphaComponent(0.12)
        imageInnerContainer.layer.cornerRadius = 24

        imageInnerContainer.addSubview(imageView)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageInnerContainer.widthAnchor.constraint(equalToConstant: 68),
            imageInnerContainer.heightAnchor.constraint(equalToConstant: 48),

            imageView.widthAnchor.constraint(equalToConstant: 32),
            imageView.heightAnchor.constraint(equalToConstant: 32),
            imageView.centerXAnchor.constraint(equalTo: imageInnerContainer.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: imageInnerContainer.centerYAnchor),
        ])

        let imageOuterContainer = UIView()
        imageOuterContainer.addSubview(imageInnerContainer)

        imageInnerContainer.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageInnerContainer.centerXAnchor.constraint(equalTo: imageOuterContainer.centerXAnchor),
            imageInnerContainer.centerYAnchor.constraint(equalTo: imageOuterContainer.centerYAnchor),
        ])

        NSLayoutConstraint.activate([
            imageOuterContainer.heightAnchor.constraint(equalToConstant: 48),
        ])

        return imageOuterContainer
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
                OWSLocalizedString(
                    "PROFILE_NAME_EDUCATION_SHEET_BULLET_4",
                    comment: "Fourth bullet point for the explainer sheet for profile names",
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
                OWSLocalizedString(
                    "GROUP_NAME_EDUCATION_SHEET_BULLET_4",
                    comment: "Fourth bullet point for the explainer sheet for group names",
                ),
            ]
        }
    }

    private class BulletPointView: UIStackView {
        init(text: String) {
            super.init(frame: .zero)

            self.axis = .horizontal
            self.alignment = .firstBaseline
            self.spacing = 8

            let label = UILabel()
            label.text = text
            label.numberOfLines = 0
            label.textColor = .label
            label.font = .dynamicTypeBody

            let bulletPoint = UILabel()
            bulletPoint.text = "•"
            bulletPoint.font = .dynamicTypeBody

            addArrangedSubview(.spacer(withWidth: 4))
            addArrangedSubview(bulletPoint)
            addArrangedSubview(label)
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
