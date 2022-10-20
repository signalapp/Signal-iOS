//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

class HiddenStoryHeaderCell: UITableViewCell {

    static let reuseIdentifier = "HiddenStoryHeaderCell"

    private let label = UILabel()
    private let iconView = UIImageView()

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

        self.backgroundColor = .clear

        label.textColor = Theme.primaryTextColor
        iconView.tintColor = Theme.primaryIconColor

        let iconName: String
        let expandedRotationAngle: CGFloat
        if CurrentAppContext().isRTL {
            iconName = "chevron-left-20"
            expandedRotationAngle = -90 * .pi / 180
        } else {
            iconName = "chevron-right-20"
            expandedRotationAngle = 90 * .pi / 180
        }
        iconView.image = .init(named: iconName)?.withRenderingMode(.alwaysTemplate)

        // Rotate the chevron down when not collapsed
        let applyIconRotation = {
            self.iconView.transform = CGAffineTransform.init(
                rotationAngle: isCollapsed ? 0 : expandedRotationAngle
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
