//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

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
        let titleLabel: UILabel
        let iconView: UIImageView
        let separatorView: UIVisualEffectView
        var highlightedView: UIView?
        var isHighlighted: Bool {
            didSet {
                if oldValue != isHighlighted {
                    if isHighlighted {
                        if highlightedView == nil {
                            let vibrancyView = UIVisualEffectView(effect: UIVibrancyEffect(blurEffect: hostEffect))
                            vibrancyView.frame = bounds
                            let view = UIView(frame: bounds)
                            view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                            view.backgroundColor = forceDarkTheme || Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_gray12
                            if forceDarkTheme || Theme.isDarkThemeEnabled {
                                vibrancyView.backgroundColor = UIColor.ows_whiteAlpha20
                            }
                            view.alpha = 0.3
                            vibrancyView.contentView.addSubview(view)
                            highlightedView = vibrancyView
                        }

                        if let view = highlightedView {
                            addSubview(view)
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
            titleLabel.numberOfLines = 2

            self.attributes = attributes
            hostEffect = hostBlurEffect
            self.forceDarkTheme = forceDarkTheme

            if attributes.contains(.destructive) {
                titleLabel.textColor = Theme.ActionSheet.default.destructiveButtonTextColor
            } else if attributes.contains(.disabled) {
                titleLabel.textColor = forceDarkTheme ? Theme.darkThemeSecondaryTextAndIconColor : Theme.secondaryTextAndIconColor
            } else {
                titleLabel.textColor = forceDarkTheme ? Theme.darkThemePrimaryColor : Theme.primaryTextColor
            }

            iconView = UIImageView(image: icon)
            iconView.contentMode = .scaleAspectFit
            iconView.tintColor = titleLabel.textColor

            separatorView = UIVisualEffectView(effect: UIVibrancyEffect(blurEffect: hostBlurEffect))
            if forceDarkTheme || Theme.isDarkThemeEnabled {
                separatorView.backgroundColor = UIColor.ows_whiteAlpha20
            }

            let separator = UIView(frame: separatorView.bounds)
            separator.backgroundColor = forceDarkTheme || Theme.isDarkThemeEnabled ? .ows_gray75 : .ows_gray22
            separator.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            separatorView.contentView.addSubview(separator)
            isHighlighted = false

            super.init(frame: CGRect.zero)

            addSubview(titleLabel)
            addSubview(iconView)
            addSubview(separatorView)

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

            if !isRTL {
                titleFrame.x = margin
                titleFrame.width = bounds.width - iconViewFrame.width - 3*margin
                iconViewFrame.x = titleFrame.maxX + margin
            } else {
                iconViewFrame.x = margin
                titleFrame.x = iconViewFrame.maxX + margin
                titleFrame.width = bounds.width - iconViewFrame.width  - 3*margin
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
        let effect = UIBlurEffect(style: .regular)
        backdropView = UIVisualEffectView(effect: effect)

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
        layer.shadowRadius = 40
        layer.shadowOffset = CGSize(width: 8, height: 20)
        layer.shadowColor = UIColor.ows_black.cgColor
        layer.shadowOpacity = 0.3

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
