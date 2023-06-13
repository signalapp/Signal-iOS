//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalUI

public class DonationReadMoreSheetViewController: InteractiveSheetViewController {
    let contentScrollView = UIScrollView()
    let stackView = UIStackView()
    public override var interactiveScrollViews: [UIScrollView] { [contentScrollView] }
    public override var sheetBackgroundColor: UIColor { Theme.tableView2PresentedBackgroundColor }

    override public func viewDidLoad() {
        super.viewDidLoad()

        minimizedHeight = 600
        super.allowsExpansion = true

        contentView.addSubview(contentScrollView)

        stackView.axis = .vertical
        stackView.layoutMargins = UIEdgeInsets(hMargin: 24, vMargin: 24)
        stackView.spacing = 32
        stackView.isLayoutMarginsRelativeArrangement = true
        contentScrollView.addSubview(stackView)
        stackView.autoPinHeightToSuperview()
        // Pin to the scroll view's viewport, not to its scrollable area
        stackView.autoPinWidth(toWidthOf: contentScrollView)

        contentScrollView.autoPinEdgesToSuperviewEdges()
        contentScrollView.alwaysBounceVertical = true

        buildContents()
    }

    private func buildContents() {
        let image = UIImage(named: "sustainer-heart")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        stackView.addArrangedSubview(imageView)

        let titleLabel = UILabel()
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.dynamicTypeTitle2.semibold()
        titleLabel.text = OWSLocalizedString(
            "DONATION_READ_MORE_SCREEN_TITLE",
            comment: "There is a screen where users can read more about their donation to Signal. This is the title of that screen."
        )
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        stackView.addArrangedSubview(titleLabel)

        let paragraphs: [String] = [
            OWSLocalizedString(
                "DONATION_READ_MORE_SCREEN_PARAGRAPH_1",
                comment: "There is a screen where users can read more about their donation to Signal. This is the 1st paragraph of that screen."
            ),
            OWSLocalizedString(
                "DONATION_READ_MORE_SCREEN_PARAGRAPH_2",
                comment: "There is a screen where users can read more about their donation to Signal. This is the 2nd paragraph of that screen."
            ),
            OWSLocalizedString(
                "DONATION_READ_MORE_SCREEN_PARAGRAPH_3",
                comment: "There is a screen where users can read more about their donation to Signal. This is the 3rd paragraph of that screen."
            )
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
