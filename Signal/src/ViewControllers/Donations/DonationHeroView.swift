//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import BonMot
import SignalServiceKit
import SignalUI

protocol DonationHeroViewDelegate: AnyObject {
    func present(readMoreSheet: DonationReadMoreSheetViewController)
}

class DonationHeroView: UIStackView {
    weak var delegate: DonationHeroViewDelegate?

    init(avatarView: UIView) {
        super.init(frame: .zero)

        self.axis = .vertical
        self.alignment = .center
        self.isLayoutMarginsRelativeArrangement = true

        self.addArrangedSubview(avatarView)
        self.setCustomSpacing(12, after: avatarView)

        let titleLabel = UILabel()
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.dynamicTypeTitle2.semibold()
        titleLabel.text = OWSLocalizedString(
            "DONATION_SCREENS_HEADER_TITLE",
            comment: "On donation screens, a small amount of information text is shown. This is the title for that text."
        )
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        self.addArrangedSubview(titleLabel)
        self.setCustomSpacing(6, after: titleLabel)

        let descriptionTextView = LinkingTextView { [weak self] in
            self?.delegate?.present(readMoreSheet: DonationReadMoreSheetViewController())
        }
        self.addArrangedSubview(descriptionTextView)

        // Others may add additional views after the description view, which is
        // why we set this spacing.
        self.setCustomSpacing(24, after: descriptionTextView)

        let descriptionBodyText = OWSLocalizedString(
            "DONATION_SCREENS_HEADER_DESCRIPTION",
            comment: "On donation screens, a small amount of information text is shown. This is the subtitle for that text."
        )
        // We'd like a link that doesn't go anywhere, because we'd like to
        // handle the tapping ourselves. We use a "fake" URL because
        // NSAttributedString needs one.
        let linkPart = StringStyle.Part.link(SupportConstants.subscriptionFAQURL)
        let readMoreText = OWSLocalizedString(
            "DONATION_SCREENS_HEADER_READ_MORE",
            comment: "On donation screens, a small amount of information text is shown. Users can click this link to learn more information."
        ).styled(with: linkPart)
        descriptionTextView.attributedText = .composed(of: [
            descriptionBodyText,
            " ",
            readMoreText
        ]).styled(with: .color(UIColor.Signal.label), .font(.dynamicTypeBody))
        descriptionTextView.linkTextAttributes = [
            .foregroundColor: UIColor.Signal.accent,
            .underlineColor: UIColor.clear,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        descriptionTextView.textAlignment = .center
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
