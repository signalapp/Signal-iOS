//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

public class ContextMenuActionsAccessory: ContextMenuTargetedPreviewAccessory, ContextMenuActionsViewDelegate {
    
    public let menu: ContextMenu
    
    private let menuView: ContextMenuActionsView
    
    public init(
        menu: ContextMenu,
        accessoryAlignment: AccessoryAlignment
    ) {
        self.menu = menu
        
        menuView = ContextMenuActionsView(menu: menu)
        super.init(accessoryView: menuView, accessoryAlignment: accessoryAlignment)
        menuView.delegate = self
    }
}

protocol ContextMenuActionsViewDelegate: AnyObject {
    
}

public class ContextMenuActionsView: UIView {
    weak var delegate: ContextMenuActionsViewDelegate?
    public let menu: ContextMenu
    
    private let actionViews: [ContextMenuActionRow]
    private let backdropView: UIVisualEffectView
    
    let cornerRadius: CGFloat = 12
    
    private class ContextMenuActionRow: UIView {
        let attributes: ContextMenuAction.Attributes
        let hostEffect: UIBlurEffect
        let titleLabel: UILabel
        let iconView: UIImageView
        let seperatorView: UIVisualEffectView
        var highlightedView: UIView? = nil
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
        let iconSize: CGFloat = 18
        
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
            let seperator = UIView(frame: seperatorView.bounds)
            seperator.backgroundColor = Theme.cellSeparatorColor
            seperator.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            seperatorView.contentView.addSubview(seperator)
            isHighlighted = false
            
            super.init(frame:CGRect.zero)
            
            addSubview(titleLabel)
            addSubview(iconView)
            addSubview(seperatorView)
        }
        
        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public override func layoutSubviews() {
            super.layoutSubviews()
            
            isHighlighted = attributes.contains(.highlighted)
            
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
    
    //MARK: UIView
    
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
    
}
