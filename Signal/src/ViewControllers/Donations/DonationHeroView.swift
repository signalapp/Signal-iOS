//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import BonMot
import SignalUI

protocol DonationHeroViewDelegate: AnyObject {
    func present(readMoreSheet: DonationReadMoreSheetViewController)
}

class DonationHeroView: UIStackView {
    private let descriptionTextView = LinkingTextView()

    public weak var delegate: DonationHeroViewDelegate?

    init(avatarView: UIView) {
        super.init(frame: .zero)

        self.axis = .vertical
        self.alignment = .center
        self.isLayoutMarginsRelativeArrangement = true
        self.spacing = 20

        self.addArrangedSubview(avatarView)
        self.setCustomSpacing(16, after: avatarView)

        let titleLabel = UILabel()
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.ows_dynamicTypeTitle2.ows_semibold
        titleLabel.text = NSLocalizedString(
            "DONATION_SCREENS_HEADER_TITLE",
            value: "Privacy over profit",
            comment: "On donation screens, a small amount of information text is shown. This is the title for that text."
        )
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        self.addArrangedSubview(titleLabel)
        self.setCustomSpacing(20, after: titleLabel)

        let descriptionBodyText = NSLocalizedString(
            "DONATION_SCREENS_HEADER_DESCRIPTION",
            value: "Private messaging, funded by you. No ads, no tracking, no compromise. Donate now to support Signal.",
            comment: "On donation screens, a small amount of information text is shown. This is the subtitle for that text."
        )
        // We'd like a link that doesn't go anywhere, because we'd like to
        // handle the tapping ourselves. We use a "fake" URL because BonMot
        // needs one.
        let linkPart = StringStyle.Part.link(SupportConstants.subscriptionFAQURL)
        let readMoreText = NSLocalizedString(
            "DONATION_SCREENS_HEADER_READ_MORE",
            value: "Read more",
            comment: "On donation screens, a small amount of information text is shown. Users can click this link to learn more information."
        ).styled(with: linkPart)
        descriptionTextView.attributedText = .composed(of: [
            descriptionBodyText,
            " ",
            readMoreText
        ]).styled(with: .color(Theme.primaryTextColor), .font(.ows_dynamicTypeBody))
        descriptionTextView.textAlignment = .center
        descriptionTextView.linkTextAttributes = [
            .foregroundColor: Theme.accentBlueColor,
            .underlineColor: UIColor.clear,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        descriptionTextView.delegate = self
        self.addArrangedSubview(descriptionTextView)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Read more

extension DonationHeroView: UITextViewDelegate {
    func textView(
        _ textView: UITextView,
        shouldInteractWith URL: URL,
        in characterRange: NSRange,
        interaction: UITextItemInteraction
    ) -> Bool {
        if textView == descriptionTextView {
            delegate?.present(readMoreSheet: DonationReadMoreSheetViewController())
        }
        return false
    }
}
