//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

class CallButton: UIButton {
    var iconName: String { didSet { updateAppearance() } }
    var selectedIconName: String? { didSet { updateAppearance() } }

    var currentIconName: String {
        if isSelected, let selectedImageName = selectedIconName {
            return selectedImageName
        }
        return iconName
    }

    var iconColor: UIColor = .ows_white { didSet { updateAppearance() } }
    var selectedIconColor: UIColor = .ows_gray75 { didSet { updateAppearance() } }
    var currentIconColor: UIColor { isSelected ? selectedIconColor : iconColor }

    var unselectedBackgroundColor = UIColor.ows_whiteAlpha40 { didSet { updateAppearance() } }
    var selectedBackgroundColor = UIColor.ows_white { didSet { updateAppearance() } }

    var currentBackgroundColor: UIColor {
        return isSelected ? selectedBackgroundColor : unselectedBackgroundColor
    }

    var text: String? { didSet { updateAppearance() } }

    override var isSelected: Bool { didSet { updateAppearance() } }
    override var isHighlighted: Bool { didSet { updateAppearance() } }

    var showDropdownArrow = false { didSet { updateDropdownArrow() } }

    var isSmall = false { didSet { updateSizing() } }

    private var currentConstraints = [NSLayoutConstraint]()

    private var currentIconSize: CGFloat { isSmall ? 48 : 56 }
    private var currentIconInsets: UIEdgeInsets {
        var insets: UIEdgeInsets
        if isSmall {
            insets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        } else {
            insets = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        }

        if showDropdownArrow {
            if CurrentAppContext().isRTL {
                insets.left += 3
                insets.right -= 3
            } else {
                insets.left -= 3
                insets.right += 3
            }
        }

        return insets
    }

    private lazy var iconView = UIImageView()
    private var dropdownIconView: UIImageView?
    private lazy var circleView = CircleView()
    private lazy var label = UILabel()

    init(iconName: String) {
        self.iconName = iconName

        super.init(frame: .zero)

        let circleViewContainer = UIView.container()
        circleViewContainer.addSubview(circleView)
        circleView.autoPinHeightToSuperview()
        circleView.autoPinEdge(toSuperviewEdge: .leading, withInset: 0, relation: .greaterThanOrEqual)
        circleView.autoPinEdge(toSuperviewEdge: .trailing, withInset: 0, relation: .greaterThanOrEqual)
        circleView.autoHCenterInSuperview()
        circleView.layer.shadowOffset = .zero
        circleView.layer.shadowOpacity = 0.25
        circleView.layer.shadowRadius = 4

        let stackView = UIStackView(arrangedSubviews: [circleViewContainer, label])
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.isUserInteractionEnabled =  false

        addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()

        label.font = .ows_dynamicTypeSubheadline
        label.textColor = Theme.darkThemePrimaryColor
        label.textAlignment = .center
        label.layer.shadowOffset = .zero
        label.layer.shadowOpacity = 0.25
        label.layer.shadowRadius = 4

        circleView.addSubview(iconView)

        updateAppearance()
        updateSizing()
    }

    private func updateAppearance() {
        circleView.backgroundColor = currentBackgroundColor
        iconView.setTemplateImageName(currentIconName, tintColor: currentIconColor)
        dropdownIconView?.setTemplateImageName("arrow-down-12", tintColor: currentIconColor)

        if let text = text {
            label.isHidden = false
            label.text = text
        } else {
            label.isHidden = true
        }

        alpha = isHighlighted ? 0.6 : 1
    }

    private func updateSizing() {
        NSLayoutConstraint.deactivate(currentConstraints)
        currentConstraints.removeAll()

        currentConstraints += circleView.autoSetDimensions(to: CGSize(square: currentIconSize))
        currentConstraints += iconView.autoPinEdgesToSuperviewEdges(with: currentIconInsets)
        if let dropdownIconView = dropdownIconView {
            currentConstraints.append(dropdownIconView.autoPinEdge(.leading, to: .trailing, of: iconView, withOffset: isSmall ? 0 : 2))
        }
    }

    private func updateDropdownArrow() {
        if showDropdownArrow {
            if dropdownIconView?.superview != nil { return }
            let dropdownIconView = UIImageView()
            self.dropdownIconView = dropdownIconView
            circleView.addSubview(dropdownIconView)

            dropdownIconView.autoSetDimensions(to: CGSize(square: 12))
            dropdownIconView.autoVCenterInSuperview()

            updateSizing()
            updateAppearance()
        } else {
            dropdownIconView?.removeFromSuperview()
            dropdownIconView = nil
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
