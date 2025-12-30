//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class DonationReadMoreSheetViewController: StackSheetViewController {
    override var stackViewInsets: UIEdgeInsets {
        UIEdgeInsets(hMargin: 24, vMargin: 24)
    }

    override var sheetBackgroundColor: UIColor { UIColor.Signal.groupedBackground }

    override func viewDidLoad() {
        super.viewDidLoad()

        stackView.spacing = 32

        let image = UIImage(named: "sustainer-heart")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        stackView.addArrangedSubview(imageView)

        let titleLabel = UILabel.title2Label(text: OWSLocalizedString(
            "DONATION_READ_MORE_SCREEN_TITLE",
            comment: "There is a screen where users can read more about their donation to Signal. This is the title of that screen.",
        ))
        stackView.addArrangedSubview(titleLabel)

        let paragraphs: [String] = [
            OWSLocalizedString(
                "DONATION_READ_MORE_SCREEN_PARAGRAPH_1",
                comment: "There is a screen where users can read more about their donation to Signal. This is the 1st paragraph of that screen.",
            ),
            OWSLocalizedString(
                "DONATION_READ_MORE_SCREEN_PARAGRAPH_2",
                comment: "There is a screen where users can read more about their donation to Signal. This is the 2nd paragraph of that screen.",
            ),
            OWSLocalizedString(
                "DONATION_READ_MORE_SCREEN_PARAGRAPH_3",
                comment: "There is a screen where users can read more about their donation to Signal. This is the 3rd paragraph of that screen.",
            ),
        ]
        for paragraph in paragraphs {
            let paragraphLabel = UILabel()
            paragraphLabel.text = paragraph
            paragraphLabel.textAlignment = .natural
            paragraphLabel.font = .dynamicTypeBody
            paragraphLabel.numberOfLines = 0
            paragraphLabel.lineBreakMode = .byWordWrapping
            stackView.addArrangedSubview(paragraphLabel)
        }
    }
}
