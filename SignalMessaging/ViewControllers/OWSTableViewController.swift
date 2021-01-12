//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public extension OWSTableItem {

    static var primaryLabelFont: UIFont {
        return UIFont.ows_dynamicTypeBodyClamped
    }

    static var accessoryLabelFont: UIFont {
        return UIFont.ows_dynamicTypeBodyClamped
    }

    static var iconSpacing: CGFloat {
        return 16
    }

    static func buildCell(name: String, iconView: UIView) -> UITableViewCell {
        return buildCell(name: name, iconView: iconView, iconSpacing: self.iconSpacing)
    }

    static func buildCell(name: String, iconView: UIView, iconSpacing: CGFloat) -> UITableViewCell {
        assert(name.count > 0)

        let cell = OWSTableItem.newCell()
        cell.preservesSuperviewLayoutMargins = true
        cell.contentView.preservesSuperviewLayoutMargins = true

        let rowLabel = UILabel()
        rowLabel.text = name
        rowLabel.textColor = Theme.primaryTextColor
        rowLabel.font = OWSTableItem.primaryLabelFont
        rowLabel.lineBreakMode = .byTruncatingTail

        let contentRow = UIStackView(arrangedSubviews: [ iconView, rowLabel ])
        contentRow.spacing = iconSpacing

        cell.contentView.addSubview(contentRow)
        contentRow.autoPinEdgesToSuperviewMargins()

        return cell
    }

    static func imageView(forIcon icon: ThemeIcon,
                          tintColor: UIColor? = nil,
                          iconSize: CGFloat = 24) -> UIImageView {
        let iconImage = Theme.iconImage(icon)
        let iconView = UIImageView(image: iconImage)
        iconView.tintColor = tintColor ?? Theme.primaryIconColor
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

    static func disclosureItem(icon: ThemeIcon,
                               name: String,
                               accessoryText: String? = nil,
                               accessibilityIdentifier: String,
                               actionBlock: (() -> Void)?) -> OWSTableItem {
        item(icon: icon,
             name: name,
             accessoryText: accessoryText,
             accessoryType: .disclosureIndicator,
             accessibilityIdentifier: accessibilityIdentifier,
             actionBlock: actionBlock)
    }

    @nonobjc
    static func actionItem(icon: ThemeIcon? = nil,
                           tintColor: UIColor? = nil,
                           name: String,
                           textColor: UIColor? = nil,
                           accessoryText: String? = nil,
                           accessibilityIdentifier: String,
                           actionBlock: (() -> Void)?) -> OWSTableItem {
        item(icon: icon,
             tintColor: tintColor,
             name: name,
             textColor: textColor,
             accessoryText: accessoryText,
             accessibilityIdentifier: accessibilityIdentifier,
             actionBlock: actionBlock)
    }

    @nonobjc
    static func item(icon: ThemeIcon? = nil,
                     tintColor: UIColor? = nil,
                     name: String,
                     textColor: UIColor? = nil,
                     accessoryText: String? = nil,
                     accessoryType: UITableViewCell.AccessoryType = .none,
                     accessibilityIdentifier: String,
                     actionBlock: (() -> Void)? = nil) -> OWSTableItem {

        OWSTableItem(customCellBlock: {
            OWSTableItem.buildCellWithAccessoryLabel(icon: icon,
                                                     tintColor: tintColor,
                                                     itemName: name,
                                                     textColor: textColor,
                                                     accessoryText: accessoryText,
                                                     accessoryType: accessoryType,
                                                     accessibilityIdentifier: accessibilityIdentifier)
            },
                     actionBlock: actionBlock)
    }

    @nonobjc
    static func buildCellWithAccessoryLabel(icon: ThemeIcon? = nil,
                                            tintColor: UIColor? = nil,
                                            itemName: String,
                                            textColor: UIColor? = nil,
                                            accessoryText: String? = nil,
                                            accessoryType: UITableViewCell.AccessoryType = .disclosureIndicator,
                                            accessibilityIdentifier: String? = nil) -> UITableViewCell {
        buildIconNameCell(icon: icon,
                          tintColor: tintColor,
                          itemName: itemName,
                          textColor: textColor,
                          accessoryText: accessoryText,
                          accessoryType: accessoryType,
                          accessibilityIdentifier: accessibilityIdentifier)
    }

    @nonobjc
    static func buildIconNameCell(icon: ThemeIcon? = nil,
                                  tintColor: UIColor? = nil,
                                  itemName: String,
                                  textColor: UIColor? = nil,
                                  accessoryText: String? = nil,
                                  accessoryType: UITableViewCell.AccessoryType = .none,
                                  customColor: UIColor? = nil,
                                  accessibilityIdentifier: String? = nil) -> UITableViewCell {

        // We can't use the built-in UITableViewCell with CellStyle.value1,
        // because if the content of the primary label and the accessory label
        // overflow the cell layout, their contents will overlap.  We want
        // the labels to truncate in that scenario.
        let cell = OWSTableItem.newCell()
        cell.preservesSuperviewLayoutMargins = true
        cell.contentView.preservesSuperviewLayoutMargins = true

        var arrangedSubviews = [UIView]()

        if let icon = icon {
            let iconView = self.imageView(forIcon: icon, tintColor: tintColor)
            iconView.setCompressionResistanceHorizontalHigh()
            arrangedSubviews.append(iconView)
            if let customColor = customColor {
                iconView.tintColor = customColor
            }
        }

        let nameLabel = UILabel()
        nameLabel.text = itemName
        if let textColor = textColor {
            nameLabel.textColor = textColor
        } else {
            nameLabel.textColor = Theme.primaryTextColor
        }
        nameLabel.font = OWSTableItem.primaryLabelFont
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setCompressionResistanceHorizontalLow()
        arrangedSubviews.append(nameLabel)
        if let customColor = customColor {
            nameLabel.textColor = customColor
        }

        if let accessoryText = accessoryText {
            let accessoryLabel = UILabel()
            accessoryLabel.text = accessoryText
            accessoryLabel.textColor = Theme.secondaryTextAndIconColor
            accessoryLabel.font = OWSTableItem.accessoryLabelFont
            accessoryLabel.lineBreakMode = .byTruncatingTail
            arrangedSubviews += [ UIView.hStretchingSpacer(), accessoryLabel ]
        }

        let contentRow = UIStackView(arrangedSubviews: arrangedSubviews)
        contentRow.spacing = self.iconSpacing
        contentRow.alignment = .center
        cell.contentView.addSubview(contentRow)
        contentRow.autoPinEdgesToSuperviewMargins()

        cell.accessibilityIdentifier = accessibilityIdentifier
        cell.accessoryType = accessoryType

        return cell
    }

    static func buildIconInCircleView(icon: ThemeIcon,
                                      innerIconSize: CGFloat) -> UIView {
        return buildIconInCircleView(icon: icon,
                                     iconSize: nil,
                                     innerIconSize: innerIconSize,
                                     iconTintColor: nil)
    }

    static func buildIconInCircleView(icon: ThemeIcon,
                                      innerIconSize: CGFloat,
                                      iconTintColor: UIColor) -> UIView {
        return buildIconInCircleView(icon: icon,
                                     iconSize: nil,
                                     innerIconSize: innerIconSize,
                                     iconTintColor: iconTintColor)
    }
}

// MARK: -

public extension OWSTableItem {
    static func buildIconInCircleView(icon: ThemeIcon,
                                      iconSize iconSizeParam: UInt? = nil,
                                      innerIconSize innerIconSizeParam: CGFloat? = nil,
                                      iconTintColor: UIColor? = nil) -> UIView {
        let iconSize = CGFloat(iconSizeParam ?? kStandardAvatarSize)
        let innerIconSize: CGFloat
        if let innerIconSizeParam = innerIconSizeParam {
            innerIconSize = innerIconSizeParam
        } else {
            innerIconSize = CGFloat(iconSize) * 0.6
        }
        let iconView = OWSTableItem.imageView(forIcon: icon, iconSize: innerIconSize)
        if let iconTintColor = iconTintColor {
            iconView.tintColor = iconTintColor
        } else {
            iconView.tintColor = Theme.accentBlueColor
        }
        let iconWrapper = UIView.container()
        iconWrapper.addSubview(iconView)
        iconView.autoCenterInSuperview()
        iconWrapper.backgroundColor = Theme.isDarkThemeEnabled ? UIColor.ows_gray80 : Theme.washColor
        iconWrapper.layer.cornerRadius = iconSize * 0.5
        iconWrapper.autoSetDimensions(to: CGSize(square: iconSize))
        iconWrapper.setCompressionResistanceHigh()
        iconWrapper.setContentHuggingHigh()
        return iconWrapper
    }
}

// MARK: - Declarative Initializers

public extension OWSTableContents {

    convenience init(title: String? = nil,
                     sections: [OWSTableSection] = []) {
        self.init()
        if let title = title {
            self.title = title
        }
        sections.forEach { section in
            self.addSection(section)
        }
    }

}

public extension OWSTableSection {

    convenience init(title: String? = nil,
                     header: UIView? = nil,
                     items: [OWSTableItem] = [],
                     footer: UIView? = nil) {

        self.init(title: title, items: items)
        self.customHeaderView = header
        self.customFooterView = footer
    }

    convenience init(title: String? = nil,
                     header: (() -> UIView?) = {nil},
                     items: [OWSTableItem] = [],
                     footer: (() -> UIView?) = {nil}) {
        self.init(title: title,
                  header: header(),
                  items: items,
                  footer: footer())
    }
}

public extension OWSTableItem {
    convenience init(
        customCell: UITableViewCell,
        rowHeight: CGFloat = UITableView.automaticDimension,
        actionBlock: OWSTableActionBlock? = nil) {

        self.init(customCell: customCell, customRowHeight: rowHeight, actionBlock: actionBlock)
    }
}
