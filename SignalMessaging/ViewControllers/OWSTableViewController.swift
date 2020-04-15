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

    static func buildCell(name: String,
                          icon: ThemeIcon,
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
                                            accessoryText: String? = nil,
                                            accessibilityIdentifier: String? = nil) -> UITableViewCell {
        let cell = buildIconNameCell(icon: icon,
                                     itemName: itemName,
                                     accessoryText: accessoryText,
                                     accessibilityIdentifier: accessibilityIdentifier)
        cell.accessoryType = .disclosureIndicator
        return cell

    }

    static func buildIconNameCell(icon: ThemeIcon,
                                  itemName: String,
                                  accessoryText: String? = nil,
                                  customColor: UIColor? = nil,
                                  accessibilityIdentifier: String? = nil) -> UITableViewCell {

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

        if let customColor = customColor {
            iconView.tintColor = customColor
            nameLabel.textColor = customColor
        }

        var arrangedSubviews = [ iconView, nameLabel ]

        if let accessoryText = accessoryText {
            let accessoryLabel = UILabel()
            accessoryLabel.text = accessoryText
            accessoryLabel.textColor = Theme.secondaryTextAndIconColor
            accessoryLabel.font = .ows_dynamicTypeBody
            accessoryLabel.lineBreakMode = .byTruncatingTail
            arrangedSubviews += [ UIView.hStretchingSpacer(), accessoryLabel ]
        }

        let contentRow = UIStackView(arrangedSubviews: arrangedSubviews)
        contentRow.spacing = self.iconSpacing
        contentRow.alignment = .center
        cell.contentView.addSubview(contentRow)
        contentRow.autoPinEdgesToSuperviewMargins()

        cell.accessibilityIdentifier = accessibilityIdentifier

        return cell
    }

    static func buildIconInCircleView(icon: ThemeIcon) -> UIView {
        let iconView = OWSTableItem.imageView(forIcon: icon)
        iconView.tintColor = .ows_accentBlue
        let iconWrapper = UIView.container()
        iconWrapper.addSubview(iconView)
        iconView.autoCenterInSuperview()
        iconWrapper.backgroundColor = Theme.washColor
        iconWrapper.layer.cornerRadius = CGFloat(kStandardAvatarSize) * 0.5
        iconWrapper.autoSetDimensions(to: CGSize(square: CGFloat(kStandardAvatarSize)))
        iconWrapper.setCompressionResistanceHigh()
        iconWrapper.setContentHuggingHigh()
        return iconWrapper
    }
}
