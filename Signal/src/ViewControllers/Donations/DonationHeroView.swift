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

        self.addArrangedSubview(avatarView)
        self.setCustomSpacing(12, after: avatarView)

        let titleLabel = UILabel()
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.ows_dynamicTypeTitle2.ows_semibold
        titleLabel.text = NSLocalizedString(
            "DONATION_SCREENS_HEADER_TITLE",
            comment: "On donation screens, a small amount of information text is shown. This is the title for that text."
        )
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        self.addArrangedSubview(titleLabel)
        self.setCustomSpacing(6, after: titleLabel)

        descriptionTextView.delegate = self
        self.addArrangedSubview(descriptionTextView)

        // Others may add additional views after the description view, which is
        // why we set this spacing.
        self.setCustomSpacing(24, after: descriptionTextView)

        rerender()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func rerender() {
        let descriptionBodyText = NSLocalizedString(
            "DONATION_SCREENS_HEADER_DESCRIPTION",
            comment: "On donation screens, a small amount of information text is shown. This is the subtitle for that text."
        )
        // We'd like a link that doesn't go anywhere, because we'd like to
        // handle the tapping ourselves. We use a "fake" URL because BonMot
        // needs one.
        let linkPart = StringStyle.Part.link(SupportConstants.subscriptionFAQURL)
        let readMoreText = NSLocalizedString(
            "DONATION_SCREENS_HEADER_READ_MORE",
            comment: "On donation screens, a small amount of information text is shown. Users can click this link to learn more information."
        ).styled(with: linkPart)
        descriptionTextView.attributedText = .composed(of: [
            descriptionBodyText,
            " ",
            readMoreText
        ]).styled(with: .color(Theme.primaryTextColor), .font(.ows_dynamicTypeBody))
        descriptionTextView.linkTextAttributes = [
            .foregroundColor: Theme.accentBlueColor,
            .underlineColor: UIColor.clear,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        descriptionTextView.textAlignment = .center
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
