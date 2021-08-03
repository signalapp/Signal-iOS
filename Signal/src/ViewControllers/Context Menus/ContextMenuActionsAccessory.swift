//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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
        accessoryAlignment: AccessoryAlignment
    ) {
        self.menu = menu

        menuView = ContextMenuActionsView(menu: menu)
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
        let alignment = delegate?.contextMenuTargetedPreviewAccessoryPreviewAlignment(self)
        let xAnchor: CGFloat
        switch alignment {
        case .center:
            xAnchor = 0.5
        case .left:
            xAnchor = 0
        case .right:
            xAnchor = 1
        case .none:
            xAnchor = 0
        }

        let frame = menuView.frame
        menuView.layer.anchorPoint = CGPoint(x: xAnchor, y: 0)
        menuView.frame = frame
    }

    override func touchLocationInViewDidChange(
        locationInView: CGPoint
    ) {
        menuView.handleGestureChanged(locationInView: locationInView)
    }

    override func touchLocationInViewDidEnd(
        locationInView: CGPoint
    ) {
        menuView.handleGestureEnded(locationInView: locationInView)
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

public class ContextMenuActionsView: UIView {

    private class ContextMenuActionRow: UIView {
        let attributes: ContextMenuAction.Attributes
        let hostEffect: UIBlurEffect
        let titleLabel: UILabel
        let iconView: UIImageView
        let seperatorView: UIVisualEffectView
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
                            view.backgroundColor = Theme.cellSelectedColor
                            if Theme.isDarkThemeEnabled {
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
        let verticalPadding: CGFloat = 20
        let iconSize: CGFloat = 22

        public init(
            title: String,
            icon: UIImage?,
            attributes: ContextMenuAction.Attributes,
            hostBlurEffect: UIBlurEffect
        ) {
            titleLabel = UILabel(frame: CGRect.zero)
            titleLabel.text = title
            titleLabel.font = UIFont.ows_dynamicTypeTitle3

            self.attributes = attributes
            hostEffect = hostBlurEffect

            if attributes.contains(.destructive) {
                titleLabel.textColor = Theme.ActionSheet.default.destructiveButtonTextColor
            } else if attributes.contains(.disabled) {
                titleLabel.textColor = Theme.secondaryTextAndIconColor
            } else {
                titleLabel.textColor = Theme.primaryTextColor
            }

            iconView = UIImageView(image: icon)
            iconView.contentMode = .scaleAspectFit
            iconView.tintColor = titleLabel.textColor

            seperatorView = UIVisualEffectView(effect: UIVibrancyEffect(blurEffect: hostBlurEffect))
            if Theme.isDarkThemeEnabled {
                seperatorView.backgroundColor = UIColor.ows_whiteAlpha20
            }

            let seperator = UIView(frame: seperatorView.bounds)
            seperator.backgroundColor = Theme.cellSeparatorColor
            seperator.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            seperatorView.contentView.addSubview(seperator)
            isHighlighted = false

            super.init(frame: CGRect.zero)

            addSubview(titleLabel)
            addSubview(iconView)
            addSubview(seperatorView)
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
            iconViewFrame.height = bounds.height

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

            var seperatorFrame = bounds
            seperatorFrame.height = 1.0 / UIScreen.main.scale
            seperatorFrame.y = bounds.maxY - seperatorFrame.height
            seperatorView.frame = seperatorFrame
        }

        public override func sizeThatFits(
            _ size: CGSize
        ) -> CGSize {
            let height = ceil(titleLabel.sizeThatFits(CGSize(width: 0, height: 0)).height) + verticalPadding
            return CGSize(width: maxWidth, height: height)
        }
    }

    weak var delegate: ContextMenuActionsViewDelegate?
    public let menu: ContextMenu

    private let actionViews: [ContextMenuActionRow]
    private let backdropView: UIVisualEffectView

    private var tapGestureRecognizer: UILongPressGestureRecognizer?

    let cornerRadius: CGFloat = 12

    public init(
        menu: ContextMenu
    ) {
        self.menu = menu

        let effect = UIBlurEffect(style: UIBlurEffect.Style.prominent)
        backdropView = UIVisualEffectView(effect: effect)

        var actionViews: [ContextMenuActionRow] = []
        for action in menu.children {
            let actionView = ContextMenuActionRow(title: action.title, icon: action.image, attributes: action.attributes, hostBlurEffect: effect)
            actionViews.append(actionView)
        }
        self.actionViews = actionViews

        super.init(frame: CGRect.zero)

        let tapGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(tapGestureRecognized(sender:)))
        tapGestureRecognizer.minimumPressDuration = 0
        addGestureRecognizer(tapGestureRecognizer)
        self.tapGestureRecognizer = tapGestureRecognizer

        layer.cornerRadius = cornerRadius
        layer.masksToBounds = true
        addSubview(backdropView)

        for actionView in actionViews {
            backdropView.contentView.addSubview(actionView)
        }

        actionViews.last?.seperatorView.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: UIView

    public override func layoutSubviews() {
        super.layoutSubviews()

        backdropView.frame = bounds
        var yOffset: CGFloat = 0
        let actionViewSize = actionViewSizeThatFits(bounds.size)
        for actionView in actionViews {
            actionView.frame = CGRect(x: 0, y: yOffset, width: actionViewSize.width, height: actionViewSize.height)
            yOffset += actionViewSize.height
        }
    }

    public override func sizeThatFits(
        _ size: CGSize
    ) -> CGSize {
        let actionViewSize = actionViewSizeThatFits(size)
        return CGSize(width: actionViewSize.width, height: actionViewSize.height * CGFloat(actionViews.count))
    }

    private func actionViewSizeThatFits(
        _ size: CGSize)
    -> CGSize {
        return actionViews.first?.sizeThatFits(size) ?? CGSize.zero
    }

    // MARK: Gestures
    @objc
    func tapGestureRecognized(sender: UIGestureRecognizer) {
        if sender.state == .began || sender.state == .changed {
            handleGestureChanged(locationInView: sender.location(in: self))
        } else if sender.state == .ended {
            handleGestureEnded(locationInView: sender.location(in: self))
        }
    }

    func handleGestureChanged(locationInView: CGPoint) {
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

    func handleGestureEnded(locationInView: CGPoint) {
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
        }
    }

}
