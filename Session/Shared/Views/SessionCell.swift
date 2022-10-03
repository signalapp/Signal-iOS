// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import DifferenceKit
import SessionUIKit
import SessionUtilitiesKit

public class SessionCell: UITableViewCell {
    public static let cornerRadius: CGFloat = 17
    
    public enum Style {
        case rounded
        case roundedEdgeToEdge
        case edgeToEdge
    }
    
    /// This value is here to allow the theming update callback to be released when preparing for reuse
    private var instanceView: UIView = UIView()
    private var position: Position?
    private var subtitleExtraView: UIView?
    private var onExtraActionTap: (() -> Void)?
    
    // MARK: - UI
    
    private var backgroundLeftConstraint: NSLayoutConstraint = NSLayoutConstraint()
    private var backgroundRightConstraint: NSLayoutConstraint = NSLayoutConstraint()
    private var topSeparatorLeftConstraint: NSLayoutConstraint = NSLayoutConstraint()
    private var topSeparatorRightConstraint: NSLayoutConstraint = NSLayoutConstraint()
    private var botSeparatorLeftConstraint: NSLayoutConstraint = NSLayoutConstraint()
    private var botSeparatorRightConstraint: NSLayoutConstraint = NSLayoutConstraint()
    private lazy var leftAccessoryFillConstraint: NSLayoutConstraint = contentStackView.set(.height, to: .height, of: leftAccessoryView)
    private lazy var rightAccessoryFillConstraint: NSLayoutConstraint = contentStackView.set(.height, to: .height, of: rightAccessoryView)// .heightAnchor.constraint(equalTo: iconImageView.heightAnchor)
    
    private let cellBackgroundView: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.clipsToBounds = true
        result.themeBackgroundColor = .settings_tabBackground
        
        return result
    }()
    
    private let cellSelectedBackgroundView: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.themeBackgroundColor = .settings_tabHighlight
        result.alpha = 0
        
        return result
    }()
    
    private let topSeparator: UIView = {
        let result: UIView = UIView.separator()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isHidden = true
        
        return result
    }()
    
    private let contentStackView: UIStackView = {
        let result: UIStackView = UIStackView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.axis = .horizontal
        result.distribution = .fill
        result.alignment = .center
        result.spacing = Values.mediumSpacing
        result.isLayoutMarginsRelativeArrangement = true
        
        return result
    }()
    
    public let leftAccessoryView: AccessoryView = {
        let result: AccessoryView = AccessoryView()
        result.isHidden = true
        
        return result
    }()
    
    private let titleStackView: UIStackView = {
        let result: UIStackView = UIStackView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.axis = .vertical
        result.distribution = .equalSpacing
        result.alignment = .fill
        result.setCompressionResistanceHorizontalLow()
        result.setContentHuggingLow()
        
        return result
    }()
    
    private let titleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.font = .boldSystemFont(ofSize: 15)
        result.themeTextColor = .textPrimary
        result.numberOfLines = 0
        result.setCompressionResistanceHorizontalLow()
        result.setContentHuggingLow()
        
        return result
    }()
    
    private let subtitleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.font = .systemFont(ofSize: 13)
        result.themeTextColor = .textPrimary
        result.numberOfLines = 0
        result.isHidden = true
        result.setCompressionResistanceHorizontalLow()
        result.setContentHuggingLow()
        
        return result
    }()
    
    private lazy var extraActionTopSpacingView: UIView = UIView.spacer(withHeight: Values.smallSpacing)
    
    private lazy var extraActionButton: UIButton = {
        let result: UIButton = UIButton()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.titleLabel?.font = .boldSystemFont(ofSize: Values.smallFontSize)
        result.titleLabel?.numberOfLines = 0
        result.contentHorizontalAlignment = .left
        result.contentEdgeInsets = UIEdgeInsets(
            top: 8,
            left: 0,
            bottom: 0,
            right: 0
        )
        result.addTarget(self, action: #selector(extraActionTapped), for: .touchUpInside)
        result.isHidden = true
        
        ThemeManager.onThemeChange(observer: result) { [weak result] theme, _ in
            switch theme.interfaceStyle {
                case .light: result?.setThemeTitleColor(.textPrimary, for: .normal)
                default: result?.setThemeTitleColor(.primary, for: .normal)
            }
        }
        
        return result
    }()
    
    public let rightAccessoryView: AccessoryView = {
        let result: AccessoryView = AccessoryView()
        result.isHidden = true
        
        return result
    }()
    
    private let botSeparator: UIView = {
        let result: UIView = UIView.separator()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isHidden = true
        
        return result
    }()
    
    // MARK: - Initialization
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        setupViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        setupViewHierarchy()
    }

    private func setupViewHierarchy() {
        self.themeBackgroundColor = .clear
        self.selectedBackgroundView = UIView()
        
        contentView.addSubview(cellBackgroundView)
        cellBackgroundView.addSubview(cellSelectedBackgroundView)
        cellBackgroundView.addSubview(topSeparator)
        cellBackgroundView.addSubview(contentStackView)
        cellBackgroundView.addSubview(botSeparator)
        
        contentStackView.addArrangedSubview(leftAccessoryView)
        contentStackView.addArrangedSubview(titleStackView)
        contentStackView.addArrangedSubview(rightAccessoryView)
        
        titleStackView.addArrangedSubview(titleLabel)
        titleStackView.addArrangedSubview(subtitleLabel)
        titleStackView.addArrangedSubview(extraActionTopSpacingView)
        titleStackView.addArrangedSubview(extraActionButton)
        
        setupLayout()
    }
    
    private func setupLayout() {
        cellBackgroundView.pin(.top, to: .top, of: contentView)
        backgroundLeftConstraint = cellBackgroundView.pin(.leading, to: .leading, of: contentView)
        backgroundRightConstraint = cellBackgroundView.pin(.trailing, to: .trailing, of: contentView)
        cellBackgroundView.pin(.bottom, to: .bottom, of: contentView)
        
        cellSelectedBackgroundView.pin(to: cellBackgroundView)
        
        topSeparator.pin(.top, to: .top, of: cellBackgroundView)
        topSeparatorLeftConstraint = topSeparator.pin(.left, to: .left, of: cellBackgroundView)
        topSeparatorRightConstraint = topSeparator.pin(.right, to: .right, of: cellBackgroundView)
        
        contentStackView.pin(to: cellBackgroundView)
        
        botSeparatorLeftConstraint = botSeparator.pin(.left, to: .left, of: cellBackgroundView)
        botSeparatorRightConstraint = botSeparator.pin(.right, to: .right, of: cellBackgroundView)
        botSeparator.pin(.bottom, to: .bottom, of: cellBackgroundView)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        // Need to force the contentStackView to layout if needed as it might not have updated it's
        // sizing yet
        self.contentStackView.layoutIfNeeded()
        
        // Position the 'subtitleExtraView' at the end of the last line of text
        if
            let subtitleExtraView: UIView = self.subtitleExtraView,
            let subtitle: String = subtitleLabel.text,
            let font: UIFont = subtitleLabel.font
        {
            let layoutManager: NSLayoutManager = NSLayoutManager()
            let textStorage = NSTextStorage(
                attributedString: NSAttributedString(
                    string: subtitle,
                    attributes: [ .font: font ]
                )
            )
            textStorage.addLayoutManager(layoutManager)
            
            let textContainer: NSTextContainer = NSTextContainer(
                size: CGSize(
                    width: subtitleLabel.bounds.size.width,
                    height: 999
                )
            )
            textContainer.lineFragmentPadding = 0
            layoutManager.addTextContainer(textContainer)
            
            var glyphRange: NSRange = NSRange()
            layoutManager.characterRange(
                forGlyphRange: NSRange(location: subtitle.glyphCount - 1, length: 1),
                actualGlyphRange: &glyphRange
            )
            let lastGlyphRect: CGRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            
            // Remove and re-add the 'subtitleExtraView' to clear any old constraints
            subtitleExtraView.removeFromSuperview()
            contentView.addSubview(subtitleExtraView)
            
            subtitleExtraView.pin(
                .top,
                to: .top,
                of: subtitleLabel,
                withInset: (lastGlyphRect.minY + ((lastGlyphRect.height / 2) - (subtitleExtraView.bounds.height / 2)))
            )
            subtitleExtraView.pin(
                .left,
                to: .left,
                of: subtitleLabel,
                withInset: lastGlyphRect.maxX
            )
        }
    }
    
    // MARK: - Content
    
    public override func prepareForReuse() {
        super.prepareForReuse()
        
        self.instanceView = UIView()
        self.position = nil
        self.onExtraActionTap = nil
        self.accessibilityIdentifier = nil
        
        leftAccessoryView.prepareForReuse()
        leftAccessoryFillConstraint.isActive = false
        titleLabel.text = ""
        titleLabel.themeTextColor = .textPrimary
        subtitleLabel.text = ""
        subtitleLabel.themeTextColor = .textPrimary
        rightAccessoryView.prepareForReuse()
        rightAccessoryFillConstraint.isActive = false
        
        topSeparator.isHidden = true
        subtitleLabel.isHidden = true
        extraActionTopSpacingView.isHidden = true
        extraActionButton.setTitle("", for: .normal)
        extraActionButton.isHidden = true
        botSeparator.isHidden = true
        
        subtitleExtraView?.removeFromSuperview()
        subtitleExtraView = nil
    }
    
    public func update<ID: Hashable & Differentiable>(
        with info: Info<ID>,
        style: Style,
        position: Position
    ) {
        self.instanceView = UIView()
        self.position = position
        self.subtitleExtraView = info.subtitleExtraViewGenerator?()
        self.onExtraActionTap = info.extraAction?.onTap
        self.accessibilityIdentifier = info.accessibilityIdentifier
        
        let leftFitToEdge: Bool = (info.leftAccessory?.shouldFitToEdge == true)
        let rightFitToEdge: Bool = (!leftFitToEdge && info.rightAccessory?.shouldFitToEdge == true)
        leftAccessoryFillConstraint.isActive = leftFitToEdge
        leftAccessoryView.update(
            with: info.leftAccessory,
            tintColor: info.tintColor,
            isEnabled: info.isEnabled
        )
        rightAccessoryView.update(
            with: info.rightAccessory,
            tintColor: info.tintColor,
            isEnabled: info.isEnabled
        )
        rightAccessoryFillConstraint.isActive = rightFitToEdge
        contentStackView.layoutMargins = UIEdgeInsets(
            top: (leftFitToEdge || rightFitToEdge ? 0 : Values.mediumSpacing),
            left: (leftFitToEdge ? 0 : Values.largeSpacing),
            bottom: (leftFitToEdge || rightFitToEdge ? 0 : Values.mediumSpacing),
            right: (rightFitToEdge ? 0 : Values.largeSpacing)
        )
        
        titleLabel.text = info.title
        titleLabel.themeTextColor = info.tintColor
        subtitleLabel.text = info.subtitle
        subtitleLabel.themeTextColor = info.tintColor
        subtitleLabel.isHidden = (info.subtitle == nil)
        extraActionTopSpacingView.isHidden = (info.extraAction == nil)
        extraActionButton.setTitle(info.extraAction?.title, for: .normal)
        extraActionButton.isHidden = (info.extraAction == nil)
        
        // Styling and positioning
        let defaultEdgePadding: CGFloat
        cellBackgroundView.themeBackgroundColor = (info.shouldHaveBackground ?
            .settings_tabBackground :
            nil
        )
        cellSelectedBackgroundView.isHidden = (!info.isEnabled || !info.shouldHaveBackground)
        
        switch style {
            case .rounded:
                defaultEdgePadding = Values.mediumSpacing
                backgroundLeftConstraint.constant = Values.largeSpacing
                backgroundRightConstraint.constant = -Values.largeSpacing
                cellBackgroundView.layer.cornerRadius = SessionCell.cornerRadius
                
            case .edgeToEdge:
                defaultEdgePadding = 0
                backgroundLeftConstraint.constant = 0
                backgroundRightConstraint.constant = 0
                cellBackgroundView.layer.cornerRadius = 0
                
            case .roundedEdgeToEdge:
                defaultEdgePadding = Values.mediumSpacing
                backgroundLeftConstraint.constant = 0
                backgroundRightConstraint.constant = 0
                cellBackgroundView.layer.cornerRadius = SessionCell.cornerRadius
        }
        
        let fittedEdgePadding: CGFloat = {
            func targetSize(accessory: Accessory?) -> CGFloat {
                switch accessory {
                    case .icon(_, let iconSize, _, _), .iconAsync(let iconSize, _, _, _):
                        return iconSize.size
                        
                    default: return defaultEdgePadding
                }
            }
            
            guard leftFitToEdge else {
                guard rightFitToEdge else { return defaultEdgePadding }
                
                return targetSize(accessory: info.rightAccessory)
            }
            
            return targetSize(accessory: info.leftAccessory)
        }()
        topSeparatorLeftConstraint.constant = (leftFitToEdge ? fittedEdgePadding : defaultEdgePadding)
        topSeparatorRightConstraint.constant = (rightFitToEdge ? -fittedEdgePadding : -defaultEdgePadding)
        botSeparatorLeftConstraint.constant = (leftFitToEdge ? fittedEdgePadding : defaultEdgePadding)
        botSeparatorRightConstraint.constant = (rightFitToEdge ? -fittedEdgePadding : -defaultEdgePadding)
        
        switch position {
            case .top:
                cellBackgroundView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
                topSeparator.isHidden = (style != .edgeToEdge)
                botSeparator.isHidden = false
                
            case .middle:
                cellBackgroundView.layer.maskedCorners = []
                topSeparator.isHidden = true
                botSeparator.isHidden = false
                
            case .bottom:
                cellBackgroundView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                topSeparator.isHidden = false
                botSeparator.isHidden = (style != .edgeToEdge)
                
            case .individual:
                cellBackgroundView.layer.maskedCorners = [
                    .layerMinXMinYCorner, .layerMaxXMinYCorner,
                    .layerMinXMaxYCorner, .layerMaxXMaxYCorner
                ]
                topSeparator.isHidden = (style != .edgeToEdge)
                botSeparator.isHidden = (style != .edgeToEdge)
        }
    }
    
    public func update(isEditing: Bool, animated: Bool) {}
    
    // MARK: - Interaction
    
    public override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        
        // If the 'cellSelectedBackgroundView' is hidden then there is no background so we
        // should update the titleLabel to indicate the highlighted state
        if cellSelectedBackgroundView.isHidden {
            titleLabel.alpha = (highlighted ? 0.8 : 1)
        }

        cellSelectedBackgroundView.alpha = (highlighted ? 1 : 0)
        leftAccessoryView.setHighlighted(highlighted, animated: animated)
        rightAccessoryView.setHighlighted(highlighted, animated: animated)
    }
    
    public override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        
        leftAccessoryView.setSelected(selected, animated: animated)
        rightAccessoryView.setSelected(selected, animated: animated)
    }
    
    @objc private func extraActionTapped() {
        onExtraActionTap?()
    }
}
