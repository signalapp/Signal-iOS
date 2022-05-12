//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

// TODO(evanhahn): This screen is not finished.
class BadgeGiftingChooseBadgeViewController: OWSTableViewController2 {
    // MARK: - Callbacks

    public override func viewDidLoad() {
        super.viewDidLoad()
        updateTableContents()
    }

    public override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    // MARK: - Table contents

    private func updateTableContents() {
        self.contents = OWSTableContents(sections: getTableSections())
    }

    private func getTableSections() -> [OWSTableSection] {
        let introSection: OWSTableSection = {
            let section = OWSTableSection()
            section.hasBackground = false
            section.customHeaderView = {
                let introStack = UIStackView()
                introStack.axis = .vertical
                introStack.spacing = 12

                let imageName = Theme.isDarkThemeEnabled ? "badge-gifting-promo-image-dark" : "badge-gifting-promo-image-light"
                let imageView = UIImageView(image: UIImage(named: imageName))
                introStack.addArrangedSubview(imageView)
                imageView.contentMode = .scaleAspectFit

                let titleLabel = UILabel()
                introStack.addArrangedSubview(titleLabel)
                titleLabel.text = NSLocalizedString("BADGE_GIFTING_CHOOSE_BADGE_TITLE",
                                               comment: "Title on the screen where you choose a gift badge")
                titleLabel.textAlignment = .center
                titleLabel.font = UIFont.ows_dynamicTypeTitle2.ows_semibold
                titleLabel.numberOfLines = 0
                titleLabel.lineBreakMode = .byWordWrapping
                titleLabel.autoPinWidthToSuperview(withMargin: 26)

                let paragraphLabel = UILabel()
                introStack.addArrangedSubview(paragraphLabel)
                paragraphLabel.text = NSLocalizedString("BADGE_GIFTING_CHOOSE_BADGE_DESCRIPTION",
                                               comment: "Short paragraph on the screen where you choose a gift badge")
                paragraphLabel.textAlignment = .center
                paragraphLabel.font = UIFont.ows_dynamicTypeBody
                paragraphLabel.numberOfLines = 0
                paragraphLabel.lineBreakMode = .byWordWrapping
                paragraphLabel.autoPinWidthToSuperview(withMargin: 26)

                return introStack
            }()
            return section
        }()

        let result: [OWSTableSection] = [introSection]

        // TODO(evanhahn): Add additional sections.

        return result
    }
}
