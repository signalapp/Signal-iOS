//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import UIKit

@objc
public extension OWSTableItem {
    enum AccessoryImageTint: Int {
        case untinted
        case tinted
    }

    static var primaryLabelFont: UIFont {
        return UIFont.ows_dynamicTypeBodyClamped
    }

    static var accessoryLabelFont: UIFont {
        return UIFont.ows_dynamicTypeBodyClamped
    }

    static var iconSpacing: CGFloat { 16 }
    static var iconSize: CGFloat { 24 }

    private static func accessoryGray() -> UIColor {
        Theme.isDarkThemeEnabled ? .ows_gray25 : .ows_gray45
    }

    static func buildCell(name: String, iconView: UIView) -> UITableViewCell {
        return buildCell(name: name, iconView: iconView, iconSpacing: self.iconSpacing)
    }

    static func buildCell(name: String, iconView: UIView, iconSpacing: CGFloat) -> UITableViewCell {
        assert(!name.isEmpty)

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
                          iconSize: CGFloat = iconSize) -> UIImageView {
        let iconImage = Theme.iconImage(icon)
        let iconView = imageView(forImage: iconImage)
        iconView.tintColor = tintColor ?? Theme.primaryIconColor
        return iconView
    }

    private static func imageView(forImage: UIImage,
                                  iconSize: CGFloat = iconSize) -> UIImageView {
        let result = UIImageView(image: forImage)
        result.contentMode = .scaleAspectFit
        result.layer.minificationFilter = .trilinear
        result.layer.magnificationFilter = .trilinear
        result.autoSetDimensions(to: CGSize(square: iconSize))
        return result
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

    @available(swift, obsoleted: 1.0)
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
    static func disclosureItem(icon: ThemeIcon,
                               name: String,
                               maxNameLines: Int? = nil,
                               accessoryText: String? = nil,
                               accessibilityIdentifier: String,
                               actionBlock: (() -> Void)?) -> OWSTableItem {
        item(icon: icon,
             name: name,
             maxNameLines: maxNameLines,
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
                           accessoryImage: UIImage? = nil,
                           accessoryImageTint: AccessoryImageTint = .tinted,
                           accessibilityIdentifier: String,
                           actionBlock: (() -> Void)?) -> OWSTableItem {
        item(icon: icon,
             tintColor: tintColor,
             name: name,
             textColor: textColor,
             accessoryText: accessoryText,
             accessoryImage: accessoryImage,
             accessoryImageTint: accessoryImageTint,
             accessibilityIdentifier: accessibilityIdentifier,
             actionBlock: actionBlock)
    }

    @nonobjc
    static func item(icon: ThemeIcon? = nil,
                     tintColor: UIColor? = nil,
                     name: String,
                     subtitle: String? = nil,
                     maxNameLines: Int? = nil,
                     textColor: UIColor? = nil,
                     accessoryText: String? = nil,
                     accessoryType: UITableViewCell.AccessoryType = .none,
                     accessoryImage: UIImage? = nil,
                     accessoryImageTint: AccessoryImageTint = .tinted,
                     accessoryView: UIView? = nil,
                     accessibilityIdentifier: String,
                     actionBlock: (() -> Void)? = nil) -> OWSTableItem {

        OWSTableItem(customCellBlock: {
            OWSTableItem.buildCellWithAccessoryLabel(
            icon: icon,
            tintColor: tintColor,
            itemName: name,
            subtitle: subtitle,
            maxItemNameLines: maxNameLines,
            textColor: textColor,
            accessoryText: accessoryText,
            accessoryType: accessoryType,
            accessoryImage: accessoryImage,
            accessoryImageTint: accessoryImageTint,
            accessoryView: accessoryView,
            accessibilityIdentifier: accessibilityIdentifier
            )
        },
                     actionBlock: actionBlock)
    }

    @available(swift, obsoleted: 1.0)
    static func buildCellWithAccessoryLabel(itemName: String,
                                            textColor: UIColor?,
                                            accessoryText: String?,
                                            accessoryType: UITableViewCell.AccessoryType,
                                            accessoryImage: UIImage?,
                                            accessibilityIdentifier: String?) -> UITableViewCell {
        buildIconNameCell(itemName: itemName,
                          textColor: textColor,
                          accessoryText: accessoryText,
                          accessoryType: accessoryType,
                          accessoryImage: accessoryImage,
                          accessibilityIdentifier: accessibilityIdentifier)
    }

    @nonobjc
    static func buildCellWithAccessoryLabel(icon: ThemeIcon? = nil,
                                            tintColor: UIColor? = nil,
                                            itemName: String,
                                            subtitle: String? = nil,
                                            maxItemNameLines: Int? = nil,
                                            textColor: UIColor? = nil,
                                            accessoryText: String? = nil,
                                            accessoryType: UITableViewCell.AccessoryType = .disclosureIndicator,
                                            accessoryImage: UIImage? = nil,
                                            accessoryImageTint: AccessoryImageTint = .tinted,
                                            accessoryView: UIView? = nil,
                                            accessibilityIdentifier: String? = nil) -> UITableViewCell {
        buildIconNameCell(icon: icon,
                          tintColor: tintColor,
                          itemName: itemName,
                          subtitle: subtitle,
                          maxItemNameLines: maxItemNameLines,
                          textColor: textColor,
                          accessoryText: accessoryText,
                          accessoryType: accessoryType,
                          accessoryImage: accessoryImage,
                          accessoryImageTint: accessoryImageTint,
                          accessoryView: accessoryView,
                          accessibilityIdentifier: accessibilityIdentifier)
    }

    @nonobjc
    static func buildIconNameCell(icon: ThemeIcon? = nil,
                                  tintColor: UIColor? = nil,
                                  itemName: String,
                                  subtitle: String? = nil,
                                  maxItemNameLines: Int? = nil,
                                  textColor: UIColor? = nil,
                                  accessoryText: String? = nil,
                                  accessoryTextColor: UIColor? = nil,
                                  accessoryType: UITableViewCell.AccessoryType = .none,
                                  accessoryImage: UIImage? = nil,
                                  accessoryImageTint: AccessoryImageTint = .tinted,
                                  accessoryView: UIView? = nil,
                                  customColor: UIColor? = nil,
                                  accessibilityIdentifier: String? = nil) -> UITableViewCell {
        var imageView: UIImageView?
        if let icon = icon {
            let iconView = self.imageView(forIcon: icon, tintColor: customColor ?? tintColor, iconSize: iconSize)
            iconView.setCompressionResistanceHorizontalHigh()
            imageView = iconView
        }
        return buildImageViewNameCell(imageView: imageView,
                                      itemName: itemName,
                                      subtitle: subtitle,
                                      maxItemNameLines: maxItemNameLines,
                                      textColor: textColor,
                                      accessoryText: accessoryText,
                                      accessoryTextColor: accessoryTextColor,
                                      accessoryType: accessoryType,
                                      accessoryImage: accessoryImage,
                                      accessoryImageTint: accessoryImageTint,
                                      accessoryView: accessoryView,
                                      customColor: customColor,
                                      accessibilityIdentifier: accessibilityIdentifier)
    }

    @nonobjc
    static func buildImageNameCell(image: UIImage? = nil,
                                   itemName: String,
                                   subtitle: String? = nil,
                                   accessoryText: String? = nil,
                                   accessoryTextColor: UIColor? = nil,
                                   accessoryType: UITableViewCell.AccessoryType = .none,
                                   accessibilityIdentifier: String? = nil) -> UITableViewCell {
        var imageView: UIImageView?
        if let image = image {
            let imgView = self.imageView(forImage: image)
            imgView.setCompressionResistanceHorizontalHigh()
            imageView = imgView
        }

        return buildImageViewNameCell(imageView: imageView,
                                      itemName: itemName,
                                      subtitle: subtitle,
                                      accessoryText: accessoryText,
                                      accessoryTextColor: accessoryTextColor,
                                      accessoryType: accessoryType,
                                      accessibilityIdentifier: accessibilityIdentifier)
    }

    @nonobjc
    private static func buildImageViewNameCell(imageView: UIImageView? = nil,
                                               tintColor: UIColor? = nil,
                                               itemName: String,
                                               subtitle: String? = nil,
                                               maxItemNameLines: Int? = nil,
                                               textColor: UIColor? = nil,
                                               accessoryText: String? = nil,
                                               accessoryTextColor: UIColor? = nil,
                                               accessoryType: UITableViewCell.AccessoryType = .none,
                                               accessoryImage: UIImage? = nil,
                                               accessoryImageTint: AccessoryImageTint = .tinted,
                                               accessoryView: UIView? = nil,
                                               customColor: UIColor? = nil,
                                               accessibilityIdentifier: String? = nil) -> UITableViewCell {

        // We can't use the built-in UITableViewCell with CellStyle.value1,
        // because if the content of the primary label and the accessory label
        // overflow the cell layout, their contents will overlap.  We want
        // the labels to truncate in that scenario.
        let cell = OWSTableItem.newCell()
        cell.preservesSuperviewLayoutMargins = true
        cell.contentView.preservesSuperviewLayoutMargins = true

        var subviews = [UIView]()

        if let imageView = imageView {
            subviews.append(imageView)
        }

        let nameLabel = UILabel()
        nameLabel.text = itemName
        if let textColor = textColor {
            nameLabel.textColor = textColor
        } else {
            nameLabel.textColor = Theme.primaryTextColor
        }
        nameLabel.font = OWSTableItem.primaryLabelFont
        nameLabel.adjustsFontForContentSizeCategory = true

        // Having two side-by-side multi-line labels makes
        // autolayout *really* confused because it doesn't
        // seem to know which height to respect (if they are
        // of different intrinsic height). It leads to lots of
        // very strange indeterminant behavior. To work around,
        // we only allow the longer of the two labels to be
        // multi-line.
        if let maxItemNameLines = maxItemNameLines {
            nameLabel.numberOfLines = maxItemNameLines
            nameLabel.lineBreakMode = .byTruncatingTail
        } else if itemName.count >= (accessoryText ?? "").count {
            nameLabel.numberOfLines = 0
            nameLabel.lineBreakMode = .byWordWrapping
        } else {
            nameLabel.numberOfLines = 1
            nameLabel.lineBreakMode = .byTruncatingTail
        }

        nameLabel.setContentHuggingLow()
        nameLabel.setCompressionResistanceHigh()

        if subtitle == nil {
            subviews.append(nameLabel)
        } else {
            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitle
            subtitleLabel.textColor = accessoryGray()
            subtitleLabel.font = .ows_dynamicTypeFootnoteClamped

            let labels = UIStackView(arrangedSubviews: [nameLabel, subtitleLabel])
            labels.axis = .vertical
            subviews.append(labels)
        }

        if let customColor = customColor {
            nameLabel.textColor = customColor
        }

        if let accessoryView = accessoryView {
            owsAssertDebug(accessoryText == nil)

            subviews.append(accessoryView)
        } else if let accessoryText = accessoryText {
            let accessoryLabel = UILabel()
            accessoryLabel.text = accessoryText
            accessoryLabel.textColor = accessoryTextColor ?? accessoryGray()
            accessoryLabel.font = OWSTableItem.accessoryLabelFont
            accessoryLabel.adjustsFontForContentSizeCategory = true

            if itemName.count >= accessoryText.count {
                accessoryLabel.numberOfLines = 1
                accessoryLabel.lineBreakMode = .byTruncatingTail
            } else {
                accessoryLabel.numberOfLines = 0
                accessoryLabel.lineBreakMode = .byWordWrapping
            }

            accessoryLabel.setCompressionResistanceHigh()
            accessoryLabel.setContentHuggingHorizontalHigh()
            accessoryLabel.setContentHuggingVerticalLow()
            subviews.append(accessoryLabel)
        }

        let contentRow = UIStackView(arrangedSubviews: subviews)
        contentRow.axis = .horizontal
        contentRow.alignment = .center
        contentRow.spacing = self.iconSpacing
        cell.contentView.addSubview(contentRow)

        contentRow.setContentHuggingHigh()
        contentRow.autoPinEdgesToSuperviewMargins()
        contentRow.autoSetDimension(.height, toSize: iconSize, relation: .greaterThanOrEqual)

        cell.accessibilityIdentifier = accessibilityIdentifier

        if let accessoryImage = accessoryImage {
            let accessoryImageView = UIImageView()

            switch accessoryImageTint {
            case .tinted:
                accessoryImageView.setTemplateImage(
                    accessoryImage,
                    // Match the OS accessory view colors
                    tintColor: Theme.isDarkThemeEnabled ? .ows_whiteAlpha25 : .ows_blackAlpha25
                )
            case .untinted:
                accessoryImageView.image = accessoryImage
            }

            accessoryImageView.sizeToFit()
            cell.accessoryView = accessoryImageView
        } else {
            cell.accessoryType = accessoryType
        }

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

public extension OWSTableContents {
    func addSections<T: Sequence>(_ sections: T) where T.Element == OWSTableSection {
        for section in sections {
            addSection(section)
        }
    }
}

// MARK: -

public extension OWSTableItem {
    static func buildIconInCircleView(icon: ThemeIcon,
                                      iconSize iconSizeParam: UInt? = nil,
                                      innerIconSize innerIconSizeParam: CGFloat? = nil,
                                      iconTintColor: UIColor? = nil) -> UIView {
        let iconSize = CGFloat(iconSizeParam ?? AvatarBuilder.standardAvatarSizePoints)
        let innerIconSize: CGFloat
        if let innerIconSizeParam = innerIconSizeParam {
            innerIconSize = innerIconSizeParam
        } else {
            innerIconSize = CGFloat(iconSize) * 0.6
        }
        let iconView = OWSTableItem.imageView(forIcon: icon, tintColor: iconTintColor ?? Theme.accentBlueColor, iconSize: innerIconSize)
        let iconWrapper = UIView.container()
        iconWrapper.addSubview(iconView)
        iconView.autoCenterInSuperview()
        iconWrapper.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray65 : .ows_gray02
        iconWrapper.layer.cornerRadius = iconSize * 0.5
        iconWrapper.autoSetDimensions(to: CGSize(square: iconSize))
        iconWrapper.setCompressionResistanceHigh()
        iconWrapper.setContentHuggingHigh()
        return iconWrapper
    }

    // Factory method for rows that display a labeled value.
    // The value can be copied to the pasteboard by tapping.
    static func copyableItem(label: String,
                             value displayValue: String?,
                             pasteboardValue: String? = nil,
                             accessibilityIdentifier: String? = nil) -> OWSTableItem {
        // If there is a custom pasteboardValue, honor it.
        // Otherwise just default to using the displayValue.
        let pasteboardValue = pasteboardValue ?? displayValue
        let accessibilityIdentifier = accessibilityIdentifier ?? label
        let displayValue = displayValue ?? OWSLocalizedString("MISSING_VALUE",
                                                             comment: "Generic indicator that no value is available for display")
        return .item(
            name: label,
            accessoryText: displayValue,
            accessibilityIdentifier: accessibilityIdentifier,
            actionBlock: {
                if let pasteboardValue = pasteboardValue {
                    UIPasteboard.general.string = pasteboardValue
                }

                guard let fromVC = CurrentAppContext().frontmostViewController() else {
                    owsFailDebug("could not identify frontmostViewController")
                    return
                }
                let toast = OWSLocalizedString("COPIED_TO_CLIPBOARD",
                                              comment: "Indicator that a value has been copied to the clipboard.")
                fromVC.presentToast(text: toast)

            }
        )
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
        self.addSections(sections)
    }

}

public extension OWSTableSection {

    convenience init(title: String? = nil,
                     items: [OWSTableItem] = [],
                     footerTitle: String? = nil) {

        self.init(title: title, items: items)
        self.footerTitle = footerTitle
    }

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
