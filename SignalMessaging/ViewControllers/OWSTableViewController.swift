//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension OWSTableItem {

    private static var iconSpacing: CGFloat {
        return 12
    }

    static func buildCell(name: String, iconView: UIView) -> UITableViewCell {
        assert(name.count > 0)

        let cell = OWSTableItem.newCell()
        cell.preservesSuperviewLayoutMargins = true
        cell.contentView.preservesSuperviewLayoutMargins = true

        let rowLabel = UILabel()
        rowLabel.text = name
        rowLabel.textColor = Theme.primaryTextColor
        rowLabel.font = .ows_dynamicTypeBody
        rowLabel.lineBreakMode = .byTruncatingTail

        let contentRow = UIStackView(arrangedSubviews: [ iconView, rowLabel ])
        contentRow.spacing = self.iconSpacing

        cell.contentView.addSubview(contentRow)
        contentRow.autoPinEdgesToSuperviewMargins()

        return cell
    }

    static func imageView(forIcon icon: ThemeIcon,
                          iconSize: CGFloat = 24) -> UIImageView {
        let iconImage = Theme.iconImage(icon)
        let iconView = UIImageView(image: iconImage)
        iconView.tintColor = Theme.primaryIconColor
        iconView.contentMode = .scaleAspectFit
        iconView.layer.minificationFilter = .trilinear
        iconView.layer.magnificationFilter = .trilinear
        iconView.autoSetDimensions(to: CGSize(square: iconSize))
        return iconView
    }

    static func buildCell(name: String, icon: ThemeIcon,
                           accessibilityIdentifier: String? = nil) -> UITableViewCell {
        let iconView = imageView(forIcon: icon)
        let cell = buildCell(name: name, iconView: iconView)
        cell.accessibilityIdentifier = accessibilityIdentifier
        return cell
    }

    static func buildDisclosureCell(name: String,
                                     icon: ThemeIcon,
                                     accessibilityIdentifier: String) -> UITableViewCell {
        let cell = buildCell(name: name, icon: icon)
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = accessibilityIdentifier
        return cell
    }

    static func buildLabelCell(name: String,
                                icon: ThemeIcon,
                                accessibilityIdentifier: String) -> UITableViewCell {
        let cell = buildCell(name: name, icon: icon)
        cell.accessoryType = .none
        cell.accessibilityIdentifier = accessibilityIdentifier
        return cell
    }

    static func buildCellWithAccessoryLabel(icon: ThemeIcon,
                                             itemName: String,
                                             accessoryText: String) -> UITableViewCell {

        // We can't use the built-in UITableViewCell with CellStyle.value1,
        // because if the content of the primary label and the accessory label
        // overflow the cell layout, their contents will overlap.  We want
        // the labels to truncate in that scenario.
        let cell = OWSTableItem.newCell()
        cell.preservesSuperviewLayoutMargins = true
        cell.contentView.preservesSuperviewLayoutMargins = true

        let iconView = self.imageView(forIcon: icon)
        iconView.setCompressionResistanceHorizontalHigh()

        let nameLabel = UILabel()
        nameLabel.text = itemName
        nameLabel.textColor = Theme.primaryTextColor
        nameLabel.font = .ows_dynamicTypeBody
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setCompressionResistanceHorizontalLow()

        let accessoryLabel = UILabel()
        accessoryLabel.text = accessoryText
        accessoryLabel.textColor = Theme.secondaryTextAndIconColor
        accessoryLabel.font = .ows_dynamicTypeBody
        accessoryLabel.lineBreakMode = .byTruncatingTail

        let contentRow =
            UIStackView(arrangedSubviews: [ iconView, nameLabel, UIView.hStretchingSpacer(), accessoryLabel ])
        contentRow.spacing = self.iconSpacing
        contentRow.alignment = .center
        cell.contentView.addSubview(contentRow)
        contentRow.autoPinEdgesToSuperviewMargins()

        cell.accessoryType = .disclosureIndicator

        return cell
    }
}
