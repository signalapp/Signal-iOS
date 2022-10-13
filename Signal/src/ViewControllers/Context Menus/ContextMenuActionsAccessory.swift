//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

public class ContextMenuActionsAccessory: ContextMenuTargetedPreviewAccessory, ContextMenuActionsViewDelegate {

    public let menu: ContextMenu

    private let menuView: ContextMenuActionsView

    private let minimumScale: CGFloat = 0.2
    private let minimumOpacity: CGFloat = 0.2
    private let springDamping: CGFloat = 0.8
    private let springInitialVelocity: CGFloat = 1

    public init(
        menu: ContextMenu,
        accessoryAlignment: AccessoryAlignment,
        forceDarkTheme: Bool = false
    ) {
        self.menu = menu

        menuView = ContextMenuActionsView(menu: menu, forceDarkTheme: forceDarkTheme)
        menuView.isHidden = true
        super.init(accessoryView: menuView, accessoryAlignment: accessoryAlignment)
        menuView.delegate = self
        animateAccessoryPresentationAlongsidePreview = true
    }

    override func animateIn(
        duration: TimeInterval,
        previewWillShift: Bool,
        completion: @escaping () -> Void
    ) {

        setMenuLayerAnchorPoint()

        menuView.transform = CGAffineTransform.scale(minimumScale)
        menuView.isHidden = false
        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: springDamping,
            initialSpringVelocity: springInitialVelocity,
            options: [.curveEaseInOut, .beginFromCurrentState],
            animations: {
                self.menuView.transform = CGAffineTransform.identity
            },
            completion: nil
        )

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = minimumOpacity
        opacityAnimation.toValue = 1
        opacityAnimation.duration = duration
        opacityAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        menuView.layer.add(opacityAnimation, forKey: "insertOpacity")
    }

    override func animateOut(
        duration: TimeInterval,
        previewWillShift: Bool,
        completion: @escaping () -> Void
    ) {

        setMenuLayerAnchorPoint()
        UIView.animate(
            withDuration: duration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState],
            animations: {
                self.menuView.transform = CGAffineTransform.scale(self.minimumScale)
            },
            completion: { _ in
                completion()
            }
        )

        let opacityAnimation = CABasicAnimation(keyPath: "opacity")
        opacityAnimation.fromValue = 1
        opacityAnimation.toValue = 0
        opacityAnimation.duration = duration - 0.1
        opacityAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        opacityAnimation.isRemovedOnCompletion = false
        opacityAnimation.fillMode = .forwards
        menuView.layer.add(opacityAnimation, forKey: "removeOpacity")
    }

    private func setMenuLayerAnchorPoint() {
        let previewAlignment = delegate?.contextMenuTargetedPreviewAccessoryPreviewAlignment(self)
        let xAnchor: CGFloat
        switch previewAlignment {
        case .center:
            xAnchor = 0.5
        case .left:
            xAnchor = 0
        case .right:
            xAnchor = 1
        case .none:
            xAnchor = 0
        }

        var yAnchor: CGFloat = 0
        alignments: for accessoryAlignment in accessoryAlignment.alignments {
            switch accessoryAlignment {
            case (.top, .exterior):
                yAnchor = 1
                break alignments
            case (.bottom, .exterior):
                yAnchor = 0
                break alignments
            default:
                break
            }
        }

        let frame = menuView.frame
        menuView.layer.anchorPoint = CGPoint(x: xAnchor, y: yAnchor)
        menuView.frame = frame
    }

    override func touchLocationInViewDidChange(
        locationInView: CGPoint
    ) {
        menuView.handleGestureChanged(locationInView: locationInView)
    }

    override func touchLocationInViewDidEnd(
        locationInView: CGPoint
    ) -> Bool {
        return menuView.handleGestureEnded(locationInView: locationInView)
    }

    func contextMenuActionViewDidSelectAction(contextMenuAction: ContextMenuAction) {
        delegate?.contextMenuTargetedPreviewAccessoryRequestsDismissal(self, completion: {
            contextMenuAction.handler(contextMenuAction)
        })
    }
}

protocol ContextMenuActionsViewDelegate: AnyObject {
    func contextMenuActionViewDidSelectAction(contextMenuAction: ContextMenuAction)
}

private class ContextMenuActionsView: UIView, UIGestureRecognizerDelegate, UIScrollViewDelegate {

    private class ContextMenuActionRow: UIView {
        let attributes: ContextMenuAction.Attributes
        let hostEffect: UIBlurEffect
        let forceDarkTheme: Bool
        let visualEffectView: UIVisualEffectView
        let titleLabel: UILabel
        let iconView: UIImageView
        let separatorView: UIView
        var highlightedView: UIView?
        var isHighlighted: Bool {
            didSet {
                if oldValue != isHighlighted {
                    if isHighlighted {
                        if highlightedView == nil {
                            let view = UIView()
                            view.frame = bounds
                            view.backgroundColor = forceDarkTheme || Theme.isDarkThemeEnabled
                                ? UIColor(rgbHex: 0x787880).withAlphaComponent(0.32)
                                : UIColor(rgbHex: 0x787880).withAlphaComponent(0.16)
                            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                            highlightedView = view
                        }

                        if let view = highlightedView {
                            insertSubview(view, at: 1)
                        }
                    } else {
                        highlightedView?.removeFromSuperview()
                    }
                }
            }
        }

        var maxWidth: CGFloat = 250
        let margin: CGFloat = 16
        let verticalPadding: CGFloat = 23
        let iconSize: CGFloat = 20
        let titleMaxLines = 2

        public init(
            title: String,
            icon: UIImage?,
            attributes: ContextMenuAction.Attributes,
            hostBlurEffect: UIBlurEffect,
            forceDarkTheme: Bool
        ) {
            titleLabel = UILabel(frame: CGRect.zero)
            titleLabel.text = title
            titleLabel.font = .ows_dynamicTypeBodyClamped
            titleLabel.numberOfLines = titleMaxLines

            self.attributes = attributes
            hostEffect = hostBlurEffect
            self.forceDarkTheme = forceDarkTheme

            /// when made a child of a UIVisualEffectView, UILabel text color is overridden, but a vibrancy effect is added.
            /// When we aren't using a color anyway, we want the vibrancy effect so we add it as a subview of the visual effect.
            /// If we want the colors to take effect, however, we make it a subview of the root view.
            let makeLabelSubviewOfVisualEffectsView: Bool
            if attributes.contains(.destructive) {
                titleLabel.textColor = Theme.ActionSheet.default.destructiveButtonTextColor
                makeLabelSubviewOfVisualEffectsView = false
            } else if attributes.contains(.disabled) {
                titleLabel.textColor = forceDarkTheme ? Theme.darkThemeSecondaryTextAndIconColor : Theme.secondaryTextAndIconColor
                makeLabelSubviewOfVisualEffectsView = false
            } else {
                titleLabel.textColor = forceDarkTheme ? Theme.darkThemePrimaryColor : Theme.primaryTextColor
                makeLabelSubviewOfVisualEffectsView = true
            }

            iconView = UIImageView(image: icon)
            iconView.contentMode = .scaleAspectFit
            iconView.tintColor = titleLabel.textColor

            separatorView = UIView()
            separatorView.backgroundColor = forceDarkTheme || Theme.isDarkThemeEnabled
                ? UIColor(rgbHex: 0x545458).withAlphaComponent(0.6)
                : UIColor(rgbHex: 0x3c3c43).withAlphaComponent(0.3)
            separatorView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            isHighlighted = false

            if #available(iOS 13, *) {
                visualEffectView = UIVisualEffectView(effect: UIVibrancyEffect(blurEffect: hostBlurEffect, style: .label))
            } else {
                visualEffectView = UIVisualEffectView(effect: UIVibrancyEffect(blurEffect: hostBlurEffect))
            }
            super.init(frame: .zero)

            addSubview(visualEffectView)
            if makeLabelSubviewOfVisualEffectsView {
                visualEffectView.contentView.addSubview(titleLabel)
            } else {
                addSubview(titleLabel)
            }
            visualEffectView.contentView.addSubview(iconView)
            visualEffectView.contentView.addSubview(separatorView)

            visualEffectView.autoPinEdgesToSuperviewEdges()

            isAccessibilityElement = true
            accessibilityLabel = titleLabel.text
            accessibilityTraits = .button
        }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public override func layoutSubviews() {
            super.layoutSubviews()

            let isRTL = CurrentAppContext().isRTL
            titleLabel.sizeToFit()
            var titleFrame = titleLabel.frame
            var iconViewFrame = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)

            titleFrame.y = ceil((bounds.height - titleFrame.height) / 2)
            iconViewFrame.y = max(0, (bounds.height - iconView.height) / 2)

            let titleWidth = bounds.width - iconViewFrame.width - 3 * margin
            if titleWidth < titleFrame.width {
                // Give it more height for a second line.
                let originalHeight = titleLabel.textRect(forBounds: CGRect.infinite, limitedToNumberOfLines: 1).height
                let multiLineHeight = titleLabel.textRect(
                    forBounds: CGRect(
                        origin: .zero,
                        size: .init(width: titleWidth, height: .infinity)
                    ),
                    limitedToNumberOfLines: titleMaxLines
                ).height
                let extraHeight = multiLineHeight - originalHeight
                titleFrame.origin.y -= extraHeight / 2
                titleFrame.height += extraHeight
            }
            titleFrame.width = titleWidth

            if !isRTL {
                titleFrame.x = margin
                iconViewFrame.x = titleFrame.maxX + margin
            } else {
                iconViewFrame.x = margin
                titleFrame.x = iconViewFrame.maxX + margin
            }

            titleLabel.frame = titleFrame
            iconView.frame = iconViewFrame

            var separatorFrame = bounds
            separatorFrame.height = 1.0 / UIScreen.main.scale
            separatorFrame.y = bounds.maxY - separatorFrame.height
            separatorView.frame = separatorFrame
        }

        public override func sizeThatFits(
            _ size: CGSize
        ) -> CGSize {
            let height = ceil(titleLabel.sizeThatFits(CGSize(width: maxWidth - 3 * margin - iconSize, height: 0)).height) + verticalPadding
            return CGSize(width: maxWidth, height: height)
        }
    }

    weak var delegate: ContextMenuActionsViewDelegate?
    public let menu: ContextMenu
    public let forceDarkTheme: Bool

    private let actionViews: [ContextMenuActionRow]
    private let scrollView: UIScrollView
    private let backdropView: UIVisualEffectView

    private var tapGestureRecognizer: UILongPressGestureRecognizer?
    private var highlightHoverGestureRecognizer: UIGestureRecognizer?

    public var isScrolling: Bool {
        didSet {
            if isScrolling && oldValue != isScrolling {
                for actionRow in actionViews {
                    actionRow.isHighlighted = false
                }
            }
        }
    }

    let cornerRadius: CGFloat = 12

    public init(
        menu: ContextMenu,
        forceDarkTheme: Bool = false
    ) {
        self.menu = menu
        self.forceDarkTheme = forceDarkTheme

        scrollView = UIScrollView(frame: CGRect.zero)
        let effect: UIBlurEffect
        if #available(iOS 13, *) {
            effect = .init(style: .systemThinMaterial)
        } else {
            effect = .init(style: .extraLight)
        }
        backdropView = UIVisualEffectView(effect: effect)
        backdropView.backgroundColor = Theme.isDarkThemeEnabled || forceDarkTheme
            ? .ows_blackAlpha80
            : .ows_whiteAlpha40

        var actionViews: [ContextMenuActionRow] = []
        for action in menu.children {
            let actionView = ContextMenuActionRow(title: action.title, icon: action.image, attributes: action.attributes, hostBlurEffect: effect, forceDarkTheme: forceDarkTheme)
            actionViews.append(actionView)
        }

        self.actionViews = actionViews
        isScrolling = false

        super.init(frame: CGRect.zero)

        let tapGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(tapGestureRecognized(sender:)))
        tapGestureRecognizer.delegate = self
        tapGestureRecognizer.minimumPressDuration = 0

        addGestureRecognizer(tapGestureRecognizer)
        self.tapGestureRecognizer = tapGestureRecognizer

        if #available(iOS 13.4, *) {
            let highlightHoverGestureRecognizer = UIHoverGestureRecognizer(target: self, action: #selector(hoverGestureRecognized(sender:)))
            highlightHoverGestureRecognizer.delegate = self
            addGestureRecognizer(highlightHoverGestureRecognizer)
            self.highlightHoverGestureRecognizer = highlightHoverGestureRecognizer
        }

        layer.cornerRadius = cornerRadius
        layer.shadowRadius = 64
        layer.shadowOffset = CGSize(width: 0, height: 32)
        layer.shadowColor = UIColor.ows_black.cgColor
        layer.shadowOpacity = 0.2

        backdropView.layer.cornerRadius = cornerRadius
        backdropView.layer.masksToBounds = true
        addSubview(backdropView)
        backdropView.contentView.addSubview(scrollView)

        for actionView in actionViews {
            scrollView.addSubview(actionView)
        }

        scrollView.delegate = self

        actionViews.last?.separatorView.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: UIView

    public override func layoutSubviews() {
        super.layoutSubviews()

        backdropView.frame = bounds
        scrollView.frame = bounds
        var yOffset: CGFloat = 0
        var maxY: CGFloat = 0
        var width: CGFloat = 0.0
        for actionView in actionViews {
            let size = actionView.sizeThatFits(.zero)
            width = max(width, size.width)
            actionView.frame = CGRect(x: 0, y: yOffset, width: width, height: size.height)
            yOffset += size.height
            maxY = max(maxY, actionView.frame.maxY)
        }

        scrollView.contentSize = CGSize(width: width, height: maxY)
    }

    public override func sizeThatFits(
        _ size: CGSize
    ) -> CGSize {
        // every entry may have a different height
        var height = 0.0
        var width = 0.0
        for actionView in actionViews {
            let size = actionView.sizeThatFits(size)
            height += size.height
            width = max(width, size.width)
        }
        return CGSize(width: width, height: height)
    }

    // MARK: Gestures
    @objc
    func tapGestureRecognized(sender: UIGestureRecognizer) {
        if sender.state == .began || sender.state == .changed {
            handleGestureChanged(locationInView: sender.location(in: scrollView))
        } else if sender.state == .ended {
            handleGestureEnded(locationInView: sender.location(in: scrollView))
        }
    }

    @objc
    func hoverGestureRecognized(sender: UIGestureRecognizer) {
        if sender.state == .began || sender.state == .changed {
            handleGestureChanged(locationInView: sender.location(in: scrollView))
        } else if sender.state == .ended {
            for actionRow in actionViews {
                actionRow.isHighlighted = false
            }
        }
    }

    func handleGestureChanged(locationInView: CGPoint) {
        guard !isScrolling else {
            return
        }

        // Add impact effect here
        var highlightStateChanged = false
        for actionRow in actionViews {
            let wasHighlighted = actionRow.isHighlighted
            let shouldHighlight = actionRow.frame.contains(locationInView) && !actionRow.attributes.contains(.disabled)
            actionRow.isHighlighted = shouldHighlight

            if !highlightStateChanged {
                highlightStateChanged = wasHighlighted != shouldHighlight
            }
        }

        if highlightStateChanged {
            ImpactHapticFeedback.impactOccured(style: .light)
        }
    }

    @discardableResult
    func handleGestureEnded(locationInView: CGPoint) -> Bool {
        guard !isScrolling else {
            return false
        }

        var index: Int = NSNotFound
        for (rowIndex, actionRow) in actionViews.enumerated() {
            if actionRow.isHighlighted && index == NSNotFound {
                index = rowIndex
            }
            actionRow.isHighlighted = false
        }

        if index != NSNotFound {
            let action = menu.children[index]
            delegate?.contextMenuActionViewDidSelectAction(contextMenuAction: action)
            return true
        }

        return false
    }

    // MARK: UIGestureRecognizerDelegate
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    // MARK: UIScrollViewDelegate

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isScrolling = true
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            isScrolling = false
        }
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        isScrolling = false
    }

}
