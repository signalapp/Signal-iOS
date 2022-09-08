//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import UIKit

class HiddenStoryHeaderCell: UITableViewCell {

    static let reuseIdentifier = "HiddenStoryHeaderCell"

    private let label = UILabel()
    private let iconView = UIImageView(image: .init(named: "chevron-right-20")?.withRenderingMode(.alwaysTemplate))

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        backgroundView = UIView()
        backgroundView?.backgroundColor = .clear
        selectionStyle = .none

        contentView.addSubview(label)
        contentView.addSubview(iconView)

        label.text = NSLocalizedString(
            "STORIES_HIDDEN_SECTION_HEADER",
            comment: "Header for the hidden stories section of the stories list"
        )
        label.font = UIFont.ows_dynamicTypeHeadline
        label.autoPinEdge(toSuperviewMargin: .leading)
        label.autoVCenterInSuperview()

        iconView.autoPinEdge(toSuperviewMargin: .trailing)
        iconView.autoVCenterInSuperview()
    }

    @available(*, unavailable, message: "use other constructor instead.")
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var isCollapsed: Bool = true

    func configure(isCollapsed: Bool, animated: Bool = true) {

        label.textColor = Theme.primaryTextColor
        iconView.tintColor = Theme.primaryIconColor

        // Rotate the chevron down when not collapsed
        let applyIconRotation = {
            self.iconView.transform = CGAffineTransform.init(
                rotationAngle: isCollapsed ? 0 : (90 * .pi / 180)
            )
        }
        defer {
            self.isCollapsed = isCollapsed
        }
        guard animated && isCollapsed != self.isCollapsed else {
            applyIconRotation()
            return
        }
        UIView.animate(withDuration: 0.2, animations: applyIconRotation)
    }
}
