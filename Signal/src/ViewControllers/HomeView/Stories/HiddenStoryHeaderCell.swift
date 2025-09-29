//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class HiddenStoryHeaderCell: UITableViewCell {

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

        label.text = OWSLocalizedString(
            "STORIES_HIDDEN_SECTION_HEADER",
            comment: "Header for the hidden stories section of the stories list"
        )
        label.font = UIFont.dynamicTypeHeadline
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

        iconView.image = UIImage(imageLiteralResourceName: "chevron-right-20")

        // Rotate the chevron down when not collapsed
        let applyIconRotation = {
            let expandedRotationAngle: CGFloat = CurrentAppContext().isRTL ? -.pi/2 : .pi/2
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
