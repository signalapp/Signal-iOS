//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class DonationReadMoreSheetViewController: InteractiveSheetViewController {
    let contentScrollView = UIScrollView()
    let stackView = UIStackView()
    public override var interactiveScrollViews: [UIScrollView] { [contentScrollView] }
    public override var sheetBackgroundColor: UIColor { Theme.tableView2PresentedBackgroundColor }

    override public func viewDidLoad() {
        super.viewDidLoad()

        minimizedHeight = 740
        super.allowsExpansion = false

        contentView.addSubview(contentScrollView)

        stackView.axis = .vertical
        stackView.layoutMargins = UIEdgeInsets(hMargin: 24, vMargin: 24)
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

        // Header image
        let image = UIImage(named: "sustainer-heart")
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        stackView.addArrangedSubview(imageView)
        stackView.setCustomSpacing(12, after: imageView)

        // Header label
        let titleLabel = UILabel()
        titleLabel.textAlignment = .natural
        titleLabel.font = UIFont.ows_dynamicTypeTitle2.ows_semibold
        titleLabel.text = NSLocalizedString(
            "SUSTAINER_READ_MORE_TITLE",
            comment: "Title for the signal sustainer read more view"
        )
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        stackView.addArrangedSubview(titleLabel)
        stackView.setCustomSpacing(12, after: titleLabel)

        let firstDescriptionBlock = UILabel()
        firstDescriptionBlock.textAlignment = .natural
        firstDescriptionBlock.font = .ows_dynamicTypeBody
        firstDescriptionBlock.text = NSLocalizedString(
            "SUSTAINER_READ_MORE_DESCRIPTION_BLOCK_ONE",
            comment: "First block of description text in read more sheet"
        )
        firstDescriptionBlock.numberOfLines = 0
        firstDescriptionBlock.lineBreakMode = .byWordWrapping
        stackView.addArrangedSubview(firstDescriptionBlock)
        stackView.setCustomSpacing(32, after: firstDescriptionBlock)

        let titleLabel2 = UILabel()
        titleLabel2.textAlignment = .natural
        titleLabel2.font = UIFont.ows_dynamicTypeTitle2.ows_semibold
        titleLabel2.text = NSLocalizedString(
            "SUSTAINER_READ_MORE_WHY_CONTRIBUTE",
            comment: "Why Contribute title for the signal sustainer read more view"
        )
        titleLabel2.numberOfLines = 0
        titleLabel2.lineBreakMode = .byWordWrapping
        stackView.addArrangedSubview(titleLabel2)
        stackView.setCustomSpacing(12, after: titleLabel2)

        let secondDescriptionBlock = UILabel()
        secondDescriptionBlock.textAlignment = .natural
        secondDescriptionBlock.font = .ows_dynamicTypeBody
        secondDescriptionBlock.text = NSLocalizedString(
            "SUSTAINER_READ_MORE_DESCRIPTION_BLOCK_TWO",
            comment: "Second block of description text in read more sheet"
        )
        secondDescriptionBlock.numberOfLines = 0
        secondDescriptionBlock.lineBreakMode = .byWordWrapping
        stackView.addArrangedSubview(secondDescriptionBlock)
    }
}
