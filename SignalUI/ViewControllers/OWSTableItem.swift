//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit

public class OWSTableItem {

    public weak var tableViewController: UIViewController?

    public private(set) var title: String?

    private var customCellBlock: (() -> UITableViewCell)?
    private var dequeueCellBlock: ((UITableView) -> UITableViewCell)?

    public private(set) var willDisplayBlock: ((UITableViewCell) -> Void)?

    public var customRowHeight: CGFloat?

    public private(set) var actionBlock: (() -> Void)?

    public private(set) var contextMenuActionProvider: UIContextMenuActionProvider?

    // MARK: -

    public init(title: String?, actionBlock: (() -> Void)?) {
        self.title = title
        self.actionBlock = actionBlock
    }

    public convenience init() {
        self.init(title: nil, actionBlock: nil)
    }

    public convenience init(
        customCellBlock: @escaping () -> UITableViewCell,
        willDisplayBlock: ((UITableViewCell) -> Void)? = nil,
        actionBlock: (() -> Void)? = nil,
        contextMenuActionProvider: UIContextMenuActionProvider? = nil
    ) {
        self.init(title: nil, actionBlock: actionBlock)
        self.customCellBlock = customCellBlock
        self.willDisplayBlock = willDisplayBlock
        self.contextMenuActionProvider = contextMenuActionProvider
    }

    public convenience init(
        dequeueCellBlock: @escaping (UITableView) -> UITableViewCell,
        actionBlock: (() -> Void)? = nil,
        contextMenuActionProvider: UIContextMenuActionProvider? = nil
    ) {
        self.init(title: nil, actionBlock: actionBlock)
        self.dequeueCellBlock = dequeueCellBlock
        self.contextMenuActionProvider = contextMenuActionProvider
    }

    public convenience init(
        text: String,
        textColor: UIColor? = nil,
        actionBlock: (() -> Void)?,
        accessoryText: String? = nil,
        accessoryType: UITableViewCell.AccessoryType,
        accessibilityIdentifier: String? = nil
    ) {
        self.init(
            customCellBlock: {
                return OWSTableItem.buildCell(
                    itemName: text,
                    textColor: textColor,
                    accessoryText: accessoryText,
                    accessoryType: accessoryType,
                    accessibilityIdentifier: accessibilityIdentifier
                )
            },
            actionBlock: actionBlock
        )
    }

    // MARK: - Convenience constructors

    public static func checkmark(
        withText text: String,
        actionBlock: (() -> Void)? = nil,
        accessibilityIdentifier: String? = nil
    ) -> OWSTableItem {
        return OWSTableItem(
            customCellBlock: {
                return OWSTableItem.buildCell(
                    itemName: text,
                    accessoryType: .checkmark,
                    accessibilityIdentifier: accessibilityIdentifier
                )
            },
            actionBlock: actionBlock
        )
    }

    public static func disclosureItem(
        icon: ThemeIcon? = nil,
        withText: String,
        maxNameLines: Int? = nil,
        accessoryText: String? = nil,
        actionBlock: (() -> Void)? = nil
    ) -> OWSTableItem {
        return item(
            icon: icon,
            name: withText,
            maxNameLines: maxNameLines,
            accessoryText: accessoryText,
            accessoryType: .disclosureIndicator,
            actionBlock: actionBlock
        )
    }

    public static func actionItem(
        withText text: String,
        textColor: UIColor? = nil,
        accessibilityIdentifier: String? = nil,
        actionBlock: (() -> Void)? = nil
    ) -> OWSTableItem {
        return OWSTableItem(
            customCellBlock: {
                return OWSTableItem.buildCell(
                    itemName: text,
                    textColor: textColor,
                    accessoryType: .disclosureIndicator,
                    accessibilityIdentifier: accessibilityIdentifier
                )
            },
            actionBlock: actionBlock
        )
    }

    public static func subpage(
        withText text: String,
        accessibilityIdentifier: String? = nil,
        actionBlock: @escaping ((UIViewController) -> Void)
    ) -> OWSTableItem {
        let item = OWSTableItem(customCellBlock: {
            return OWSTableItem.buildCell(
                itemName: text,
                accessoryType: .disclosureIndicator,
                accessibilityIdentifier: accessibilityIdentifier
            )
        })

        item.actionBlock = { [weak item] in
            guard let item else { return }
            guard let viewController = item.tableViewController else {
                owsFailDebug("viewController == nil")
                return
            }
            actionBlock(viewController)
        }

        return item
    }

    public static func softCenterLabel(
        withText text: String
    ) -> OWSTableItem {
        return OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.newCell()
            let textLabel = UILabel()
            textLabel.text = text
            // These cells look quite different.
            //
            // Smaller font.
            textLabel.font = OWSTableItem.primaryLabelFont
            // Soft color.
            // TODO: Theme, review with design.
            textLabel.textColor = UIColor.ows_middleGray
            // Centered.
            textLabel.textAlignment = .center
            cell.contentView.addSubview(textLabel)
            textLabel.autoPinEdgesToSuperviewMargins()
            cell.isUserInteractionEnabled = false
            return cell
        })
    }

    public static func label(
        withText text: String,
        accessoryText: String? = nil,
        accessoryType: UITableViewCell.AccessoryType = .disclosureIndicator
    ) -> OWSTableItem {
        return OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.buildCell(
                itemName: text,
                accessoryText: accessoryText,
                accessoryType: accessoryType
            )

            cell.isUserInteractionEnabled = false

            return cell
        })
    }

    public static func longDisclosure(
        withText text: String,
        actionBlock: (() -> Void)? = nil
    ) -> OWSTableItem {
        return OWSTableItem(
            customCellBlock: {
                let cell = OWSTableItem.newCell()
                cell.accessoryType = .disclosureIndicator

                let textLabel = UILabel()
                textLabel.text = text
                textLabel.numberOfLines = 0
                textLabel.lineBreakMode = .byWordWrapping
                cell.contentView.addSubview(textLabel)
                textLabel.autoPinEdgesToSuperviewMargins()

                return cell
            },
            actionBlock: actionBlock
        )
    }

    public static func `switch`(
        withText text: String,
        accessibilityIdentifier: String? = nil,
        isOn: @escaping (() -> Bool),
        isEnabled: @escaping (() -> Bool) = { true },
        target: AnyObject,
        selector: Selector
    ) -> OWSTableItem {
        return OWSTableItem(customCellBlock: { [weak target] in
            let cell = OWSTableItem.buildCell(
                itemName: text,
                accessibilityIdentifier: accessibilityIdentifier
            )

            let cellSwitch = UISwitch()
            cellSwitch.isOn = isOn()
            cellSwitch.isEnabled = isEnabled()
            cellSwitch.accessibilityIdentifier = accessibilityIdentifier
            cellSwitch.addTarget(target, action: selector, for: .valueChanged)

            cell.accessoryView = cellSwitch
            cell.selectionStyle = .none
            return cell
        })
    }

    public static func `switch`(
        withText text: String,
        subtitle: String? = nil,
        accessibilityIdentifier: String? = nil,
        isOn: @escaping (() -> Bool),
        isEnabled: @escaping (() -> Bool) = { true },
        actionBlock: @escaping ((UISwitch) -> Void) = { _ in }
    ) -> OWSTableItem {
        return OWSTableItem(customCellBlock: {
            let cell = OWSTableItem.buildCell(
                itemName: text,
                subtitle: subtitle,
                accessibilityIdentifier: accessibilityIdentifier
            )

            let cellSwitch = UISwitch()
            cellSwitch.isOn = isOn()
            cellSwitch.isEnabled = isEnabled()
            cellSwitch.accessibilityIdentifier = accessibilityIdentifier
            cellSwitch.addAction(UIAction(handler: { [unowned cellSwitch] _ in actionBlock(cellSwitch) }), for: .valueChanged)

            cell.accessoryView = cellSwitch
            cell.selectionStyle = .none
            return cell
        })
    }

    // MARK: - Table View Cells

    public class func newCell() -> UITableViewCell {
        let cell = UITableViewCell()
        configureCell(cell)
        return cell
    }

    public class func configureCell(_ cell: UITableViewCell) {
        cell.selectedBackgroundView = UIView()
        cell.backgroundColor = Theme.backgroundColor
        cell.selectedBackgroundView?.backgroundColor = Theme.tableCell2SelectedBackgroundColor
        cell.multipleSelectionBackgroundView?.backgroundColor = Theme.tableCell2MultiSelectedBackgroundColor
        configureCellLabels(cell)
    }

    private class func configureCellLabels(_ cell: UITableViewCell) {
        cell.textLabel?.font = self.primaryLabelFont
        cell.textLabel?.textColor = Theme.primaryTextColor
        cell.detailTextLabel?.textColor = Theme.secondaryTextAndIconColor
        cell.detailTextLabel?.font = OWSTableItem.accessoryLabelFont
    }

    func getOrBuildCustomCell(_ tableView: UITableView) -> UITableViewCell? {
        if let customCellBlock {
            owsAssertDebug(dequeueCellBlock == nil)
            return customCellBlock()
        }
        if let dequeueCellBlock {
            return dequeueCellBlock(tableView)
        }
        return nil
    }
}

public extension OWSTableItem {

    static var primaryLabelFont: UIFont { .dynamicTypeBodyClamped }
    static var accessoryLabelFont: UIFont { .dynamicTypeBodyClamped }

    static var iconSpacing: CGFloat { 16 }
    static var iconSize: CGFloat { 24 }

    private static func accessoryGray() -> UIColor {
        Theme.isDarkThemeEnabled ? .ows_gray25 : .ows_gray45
    }

    static func imageView(
        forIcon icon: ThemeIcon,
        tintColor: UIColor? = nil,
        iconSize: CGFloat = iconSize
    ) -> UIImageView {
        let iconImage = Theme.iconImage(icon)
        let iconView = imageView(forImage: iconImage)
        iconView.tintColor = tintColor ?? Theme.primaryIconColor
        iconView.autoSetDimensions(to: .square(iconSize))
        return iconView
    }

    private static func imageView(
        forImage: UIImage,
        iconSize: CGFloat = iconSize
    ) -> UIImageView {
        let result = UIImageView(image: forImage)
        result.contentMode = .scaleAspectFit
        result.layer.minificationFilter = .trilinear
        result.layer.magnificationFilter = .trilinear
        result.autoSetDimensions(to: CGSize(square: iconSize))
        return result
    }

    static func item(
        icon: ThemeIcon? = nil,
        tintColor: UIColor? = nil,
        name: String,
        subtitle: String? = nil,
        maxNameLines: Int? = nil,
        textColor: UIColor? = nil,
        accessoryText: String? = nil,
        accessoryType: UITableViewCell.AccessoryType = .none,
        accessoryContentView: UIView? = nil,
        accessibilityIdentifier: String? = nil,
        actionBlock: (() -> Void)? = nil
    ) -> OWSTableItem {
        return OWSTableItem(
            customCellBlock: {
                OWSTableItem.buildCell(
                    icon: icon,
                    tintColor: tintColor,
                    itemName: name,
                    subtitle: subtitle,
                    maxItemNameLines: maxNameLines,
                    textColor: textColor,
                    accessoryText: accessoryText,
                    accessoryType: accessoryType,
                    accessoryContentView: accessoryContentView,
                    accessibilityIdentifier: accessibilityIdentifier
                )
            },
            actionBlock: actionBlock
        )
    }

    static func buildCell(
        icon: ThemeIcon? = nil,
        tintColor: UIColor? = nil,
        itemName: String,
        subtitle: String? = nil,
        maxItemNameLines: Int? = nil,
        textColor: UIColor? = nil,
        accessoryText: String? = nil,
        accessoryTextColor: UIColor? = nil,
        accessoryType: UITableViewCell.AccessoryType = .none,
        accessoryContentView: UIView? = nil,
        customColor: UIColor? = nil,
        accessibilityIdentifier: String? = nil
    ) -> UITableViewCell {
        var imageView: UIImageView?
        if let icon = icon {
            let iconView = self.imageView(forIcon: icon, tintColor: customColor ?? tintColor, iconSize: iconSize)
            iconView.setCompressionResistanceHorizontalHigh()
            imageView = iconView
        }

        return buildImageViewCell(
            imageView: imageView,
            itemName: itemName,
            subtitle: subtitle,
            maxItemNameLines: maxItemNameLines,
            textColor: textColor,
            accessoryText: accessoryText,
            accessoryTextColor: accessoryTextColor,
            accessoryType: accessoryType,
            accessoryContentView: accessoryContentView,
            customColor: customColor,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }

    static func buildImageCell(
        image: UIImage? = nil,
        itemName: String,
        subtitle: String? = nil,
        maxItemNameLines: Int? = nil,
        accessoryText: String? = nil,
        accessoryTextColor: UIColor? = nil,
        accessoryType: UITableViewCell.AccessoryType = .none,
        accessoryContentView: UIView? = nil,
        accessibilityIdentifier: String? = nil
    ) -> UITableViewCell {
        var imageView: UIImageView?
        if let image = image {
            let imgView = self.imageView(forImage: image)
            imgView.setCompressionResistanceHorizontalHigh()
            imageView = imgView
        }

        return buildImageViewCell(
            imageView: imageView,
            itemName: itemName,
            subtitle: subtitle,
            maxItemNameLines: maxItemNameLines,
            accessoryText: accessoryText,
            accessoryTextColor: accessoryTextColor,
            accessoryType: accessoryType,
            accessoryContentView: accessoryContentView,
            accessibilityIdentifier: accessibilityIdentifier
        )
    }

    private static func buildImageViewCell(
        imageView: UIImageView? = nil,
        tintColor: UIColor? = nil,
        itemName: String,
        subtitle: String? = nil,
        maxItemNameLines: Int? = nil,
        textColor: UIColor? = nil,
        accessoryText: String? = nil,
        accessoryTextColor: UIColor? = nil,
        accessoryType: UITableViewCell.AccessoryType = .none,
        accessoryContentView: UIView? = nil,
        customColor: UIColor? = nil,
        accessibilityIdentifier: String? = nil
    ) -> UITableViewCell {
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
            nameLabel.setCompressionResistanceHorizontalHigh()
        } else if itemName.count >= (accessoryText ?? "").count {
            nameLabel.numberOfLines = 0
            nameLabel.lineBreakMode = .byWordWrapping
            nameLabel.setCompressionResistanceHorizontalLow()
        } else {
            nameLabel.numberOfLines = 1
            nameLabel.lineBreakMode = .byTruncatingTail
            nameLabel.setCompressionResistanceHorizontalHigh()
        }

        nameLabel.setContentHuggingLow()
        nameLabel.setCompressionResistanceVerticalHigh()

        if subtitle == nil {
            subviews.append(nameLabel)
        } else {
            let subtitleLabel = UILabel()
            subtitleLabel.text = subtitle
            subtitleLabel.numberOfLines = 0
            subtitleLabel.textColor = accessoryGray()
            subtitleLabel.font = .dynamicTypeFootnoteClamped

            let labels = UIStackView(arrangedSubviews: [nameLabel, subtitleLabel])
            labels.axis = .vertical
            subviews.append(labels)
        }

        if let customColor = customColor {
            nameLabel.textColor = customColor
        }

        if let accessoryContentView {
            owsAssertDebug(accessoryText == nil)

            subviews.append(accessoryContentView)
        } else if let accessoryText {
            let accessoryLabel = UILabel()
            accessoryLabel.text = accessoryText
            accessoryLabel.textColor = accessoryTextColor ?? accessoryGray()
            accessoryLabel.font = OWSTableItem.accessoryLabelFont
            accessoryLabel.adjustsFontForContentSizeCategory = true

            if itemName.count >= accessoryText.count {
                accessoryLabel.numberOfLines = 1
                accessoryLabel.lineBreakMode = .byTruncatingTail
                accessoryLabel.setCompressionResistanceHorizontalHigh()
            } else {
                accessoryLabel.numberOfLines = 0
                accessoryLabel.lineBreakMode = .byWordWrapping
                accessoryLabel.setCompressionResistanceHorizontalLow()
            }

            accessoryLabel.setCompressionResistanceVerticalHigh()
            accessoryLabel.setContentHuggingHorizontalHigh()
            accessoryLabel.setContentHuggingVerticalLow()
            subviews.append(accessoryLabel)
        }

        let contentRow = UIStackView(arrangedSubviews: subviews)
        contentRow.axis = .horizontal
        contentRow.alignment = .center
        contentRow.spacing = self.iconSpacing

        contentRow.setContentHuggingHigh()
        contentRow.autoSetDimension(.height, toSize: iconSize, relation: .greaterThanOrEqual)

        cell.contentView.addSubview(contentRow)
        contentRow.autoPinEdgesToSuperviewMargins()

        cell.accessibilityIdentifier = accessibilityIdentifier
        cell.accessoryType = accessoryType

        return cell
    }
}

// MARK: -

public extension OWSTableItem {
    static func buildIconInCircleView(
        icon: ThemeIcon,
        iconSize iconSizeParam: UInt,
        innerIconSize: CGFloat,
        iconTintColor: UIColor
    ) -> UIView {
        let iconSize = CGFloat(iconSizeParam)
        let iconView = OWSTableItem.imageView(forIcon: icon, tintColor: iconTintColor, iconSize: innerIconSize)
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
}

// MARK: - Copyable item

public extension OWSTableItem {

    /// An item that displays a labeled value that is copied on selection. A
    /// toast is presented on selection.
    ///
    /// - Parameter value
    /// The value to display, if any.
    /// - Parameter pasteboardValue
    /// The value to copy, if different than ``value``.
    static func copyableItem(
        label: String,
        subtitle: String? = nil,
        value displayValue: String?,
        pasteboardValue: String? = nil,
        accessibilityIdentifier: String? = nil
    ) -> OWSTableItem {
        let pasteboardValue = pasteboardValue ?? displayValue
        let accessibilityIdentifier = accessibilityIdentifier ?? label

        return .item(
            name: label,
            subtitle: subtitle,
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

                let toast = OWSLocalizedString(
                    "COPIED_TO_CLIPBOARD",
                    comment: "Indicator that a value has been copied to the clipboard."
                )

                fromVC.presentToast(text: toast)
            }
        )
    }
}

// MARK: - Item wrapping custom view

public extension OWSTableItem {
    private class ViewWrappingTableViewCell: UITableViewCell {
        init(viewToWrap: UIView, margins: UIEdgeInsets) {
            super.init(style: .default, reuseIdentifier: nil)

            selectionStyle = .none

            contentView.addSubview(viewToWrap)
            contentView.layoutMargins = margins

            viewToWrap.autoPinEdgesToSuperviewMargins()
        }

        required init?(coder: NSCoder) {
            owsFail("Not implemented!")
        }
    }

    static func itemWrappingView(
        viewBlock: @escaping () -> UIView?,
        margins: UIEdgeInsets
    ) -> OWSTableItem {
        return OWSTableItem(customCellBlock: {
            guard let view = viewBlock() else {
                return UITableViewCell()
            }

            return ViewWrappingTableViewCell(
                viewToWrap: view,
                margins: margins
            )
        })
    }
}

// MARK: - Text field item

public extension OWSTableItem {
    // [Colors] TODO: When proper dynamic colors are added, the `textColor`
    // property here should be moved to `OWSTextField` since it won't need to be
    // explicitly updated when the table refreshes.
    /// Creates an ``OWSTableItem`` with the text field while optionally setting
    /// its font and/or text color.
    /// - Parameters:
    ///   - textField: The text field to use in the table item's cell.
    ///   - textColor: The text color to set on the text field.
    ///   If this value is `nil`, the text color will not be modified.
    ///   Default value is `nil`.
    /// - Returns: An ``OWSTableItem`` with the `textField` embedded.
    static func textFieldItem(
        _ textField: UITextField,
        textColor: @escaping @autoclosure () -> UIColor? = Theme.primaryTextColor
    ) -> OWSTableItem {
        .init(customCellBlock: {
            if let textColor = textColor() {
                textField.textColor = textColor
            }

            let cell = Self.newCell()
            cell.selectionStyle = .none
            cell.addSubview(textField)
            textField.autoPinEdgesToSuperviewMargins()
            return cell
        }, actionBlock: {
            textField.becomeFirstResponder()
        })
    }
}
