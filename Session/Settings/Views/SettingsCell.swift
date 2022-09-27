// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import SessionUIKit

class SettingsCell: UITableViewCell {
    public static let cornerRadius: CGFloat = 17
    
    enum Style {
        case rounded
        case edgeToEdge
    }
    
    /// This value is here to allow the theming update callback to be released when preparing for reuse
    private var instanceView: UIView = UIView()
    private var position: Position?
    private var subtitleExtraView: UIView?
    private var onExtraAction: (() -> Void)?
    
    // MARK: - UI
    
    private var backgroundLeftConstraint: NSLayoutConstraint = NSLayoutConstraint()
    private var backgroundRightConstraint: NSLayoutConstraint = NSLayoutConstraint()
    private var topSeparatorLeftConstraint: NSLayoutConstraint = NSLayoutConstraint()
    private var topSeparatorRightConstraint: NSLayoutConstraint = NSLayoutConstraint()
    private var botSeparatorLeftConstraint: NSLayoutConstraint = NSLayoutConstraint()
    private var botSeparatorRightConstraint: NSLayoutConstraint = NSLayoutConstraint()
    private lazy var stackViewImageHeightConstraint: NSLayoutConstraint = contentStackView.heightAnchor.constraint(equalTo: iconImageView.heightAnchor)
    
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
    
    private let iconImageView: UIImageView = {
        let result: UIImageView = UIImageView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.contentMode = .scaleAspectFit
        result.themeTintColor = .textPrimary
        result.layer.minificationFilter = .trilinear
        result.layer.magnificationFilter = .trilinear
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
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.themeTextColor = .textPrimary
        result.numberOfLines = 0
        result.setCompressionResistanceHorizontalLow()
        result.setContentHuggingLow()
        
        return result
    }()
    
    private let subtitleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.font = .systemFont(ofSize: Values.smallFontSize)
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
    
    private let pushChevronImageView: UIImageView = {
        let result: UIImageView = UIImageView(image: UIImage(systemName: "chevron.right"))
        result.translatesAutoresizingMaskIntoConstraints = false
        result.themeTintColor = .textPrimary
        result.isHidden = true
        result.setContentHuggingHigh()
        result.setCompressionResistanceHigh()
        
        return result
    }()
    
    private let toggleSwitch: UISwitch = {
        let result: UISwitch = UISwitch()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isUserInteractionEnabled = false // Triggered by didSelectCell instead
        result.themeOnTintColor = .primary
        result.isHidden = true
        result.setContentHuggingHigh()
        result.setCompressionResistanceHigh()
        
        return result
    }()
    
    private let dropDownStackView: UIStackView = {
        let result: UIStackView = UIStackView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.axis = .horizontal
        result.distribution = .fill
        result.alignment = .center
        result.spacing = Values.verySmallSpacing
        result.isHidden = true
        
        return result
    }()
    
    private let dropDownImageView: UIImageView = {
        let result: UIImageView = UIImageView(image: UIImage(systemName: "arrowtriangle.down.fill"))
        result.translatesAutoresizingMaskIntoConstraints = false
        result.themeTintColor = .textPrimary
        result.set(.width, to: 10)
        result.set(.height, to: 10)
        
        return result
    }()
    
    private let dropDownLabel: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.font = .systemFont(ofSize: Values.smallFontSize, weight: .medium)
        result.themeTextColor = .textPrimary
        result.setContentHuggingHigh()
        result.setCompressionResistanceHigh()
        
        return result
    }()
    
    private let tickImageView: UIImageView = {
        let result: UIImageView = UIImageView(image: UIImage(systemName: "checkmark"))
        result.translatesAutoresizingMaskIntoConstraints = false
        result.themeTintColor = .primary
        result.isHidden = true
        result.setContentHuggingHigh()
        result.setCompressionResistanceHigh()
        
        return result
    }()
    
    public lazy var rightActionButtonContainerView: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.themeBackgroundColor = .solidButton_background
        result.layer.cornerRadius = 5
        result.isHidden = true
        
        return result
    }()
    
    private lazy var rightActionButtonLabel: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.font = .boldSystemFont(ofSize: Values.smallFontSize)
        result.themeTextColor = .textPrimary
        result.setContentHuggingHigh()
        result.setCompressionResistanceHigh()
        
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
        
        contentStackView.addArrangedSubview(iconImageView)
        contentStackView.addArrangedSubview(titleStackView)
        contentStackView.addArrangedSubview(pushChevronImageView)
        contentStackView.addArrangedSubview(toggleSwitch)
        contentStackView.addArrangedSubview(tickImageView)
        contentStackView.addArrangedSubview(dropDownStackView)
        contentStackView.addArrangedSubview(rightActionButtonContainerView)
        
        titleStackView.addArrangedSubview(titleLabel)
        titleStackView.addArrangedSubview(subtitleLabel)
        titleStackView.addArrangedSubview(extraActionTopSpacingView)
        titleStackView.addArrangedSubview(extraActionButton)
        
        dropDownStackView.addArrangedSubview(dropDownImageView)
        dropDownStackView.addArrangedSubview(dropDownLabel)
        
        rightActionButtonContainerView.addSubview(rightActionButtonLabel)
        
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
        
        rightActionButtonContainerView.center(.vertical, in: contentStackView)
        rightActionButtonLabel.pin(to: rightActionButtonContainerView, withInset: Values.smallSpacing)
        
        botSeparatorLeftConstraint = botSeparator.pin(.left, to: .left, of: cellBackgroundView)
        botSeparatorRightConstraint = botSeparator.pin(.right, to: .right, of: cellBackgroundView)
        botSeparator.pin(.bottom, to: .bottom, of: cellBackgroundView)
    }
    
    override func layoutSubviews() {
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
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        self.instanceView = UIView()
        self.position = nil
        self.onExtraAction = nil
        self.accessibilityIdentifier = nil
        
        stackViewImageHeightConstraint.isActive = false
        iconImageView.removeConstraints(iconImageView.constraints)
        iconImageView.image = nil
        iconImageView.themeTintColor = .textPrimary
        titleLabel.text = ""
        titleLabel.themeTextColor = .textPrimary
        subtitleLabel.text = ""
        dropDownLabel.text = ""
        
        topSeparator.isHidden = true
        iconImageView.isHidden = true
        subtitleLabel.isHidden = true
        extraActionTopSpacingView.isHidden = true
        extraActionButton.setTitle("", for: .normal)
        extraActionButton.isHidden = true
        pushChevronImageView.isHidden = true
        toggleSwitch.isHidden = true
        dropDownStackView.isHidden = true
        tickImageView.isHidden = true
        tickImageView.alpha = 1
        rightActionButtonContainerView.isHidden = true
        botSeparator.isHidden = true
        
        subtitleExtraView?.removeFromSuperview()
        subtitleExtraView = nil
    }
    
    public func update(
        style: Style = .rounded,
        icon: UIImage?,
        iconSize: IconSize,
        iconSetter: ((UIImageView) -> Void)?,
        title: String,
        subtitle: String?,
        alignment: NSTextAlignment,
        accessibilityIdentifier: String?,
        subtitleExtraViewGenerator: (() -> UIView)?,
        action: SettingsAction,
        extraActionTitle: String?,
        onExtraAction: (() -> Void)?,
        position: Position
    ) {
        self.instanceView = UIView()
        self.position = position
        self.subtitleExtraView = subtitleExtraViewGenerator?()
        self.onExtraAction = onExtraAction
        self.accessibilityIdentifier = accessibilityIdentifier
        
        stackViewImageHeightConstraint.isActive = {
            switch iconSize {
                case .small, .medium: return false
                case .large: return true   // Edge-to-edge in this case
            }
        }()
        contentStackView.layoutMargins = UIEdgeInsets(
            top: Values.mediumSpacing,
            leading: {
                switch iconSize {
                    case .small, .medium: return Values.largeSpacing
                    case .large: return 0   // Edge-to-edge in this case
                }
            }(),
            bottom: Values.mediumSpacing,
            trailing: Values.largeSpacing
        )
        
        // Left content
        iconImageView.set(.width, to: iconSize.size)
        iconImageView.set(.height, to: iconSize.size)
        iconImageView.image = icon
        iconImageView.isHidden = (icon == nil && iconSetter == nil)
        titleLabel.text = title
        titleLabel.textAlignment = alignment
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = (subtitle == nil)
        extraActionTopSpacingView.isHidden = (extraActionTitle == nil)
        extraActionButton.setTitle(extraActionTitle, for: .normal)
        extraActionButton.isHidden = (extraActionTitle == nil)
        
        // Call the iconSetter closure if provided to set the icon
        iconSetter?(iconImageView)
        
        // Styling and positioning
        cellBackgroundView.themeBackgroundColor = (action.shouldHaveBackground ?
            .settings_tabBackground :
            nil
        )
        cellSelectedBackgroundView.isHidden = !action.shouldHaveBackground
        backgroundLeftConstraint.constant = (style == .rounded ? Values.largeSpacing : 0)
        backgroundRightConstraint.constant = (style == .rounded ? -Values.largeSpacing : 0)
        topSeparatorLeftConstraint.constant = (style == .rounded ? Values.mediumSpacing : 0)
        topSeparatorRightConstraint.constant = (style == .rounded ? -Values.mediumSpacing : 0)
        botSeparatorLeftConstraint.constant = (style == .rounded ? Values.mediumSpacing : 0)
        botSeparatorRightConstraint.constant = (style == .rounded ? -Values.mediumSpacing : 0)
        cellBackgroundView.layer.cornerRadius = (style == .rounded ? SettingsCell.cornerRadius : 0)
        
        switch position {
            case .top:
                cellBackgroundView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
                topSeparator.isHidden = true
                botSeparator.isHidden = false
                
            case .middle:
                cellBackgroundView.layer.maskedCorners = []
                topSeparator.isHidden = true
                botSeparator.isHidden = false
                
            case .bottom:
                cellBackgroundView.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                botSeparator.isHidden = false
                botSeparator.isHidden = true
                
            case .individual:
                cellBackgroundView.layer.maskedCorners = [
                    .layerMinXMinYCorner, .layerMaxXMinYCorner,
                    .layerMinXMaxYCorner, .layerMaxXMaxYCorner
                ]
                topSeparator.isHidden = true
                botSeparator.isHidden = true
        }
        
        // Action Behaviours
        switch action {
            case .threadInfo: break
            
            case .userDefaultsBool(let defaults, let key, let isEnabled, _):
                toggleSwitch.isHidden = false
                toggleSwitch.isEnabled = isEnabled
                
                // Remove the selection view if the setting is disabled
                cellSelectedBackgroundView.isHidden = !isEnabled
                
                let newValue: Bool = defaults.bool(forKey: key)
                
                if newValue != toggleSwitch.isOn {
                    toggleSwitch.setOn(newValue, animated: true)
                }
            
            case .settingBool(let key, _, let isEnabled):
                toggleSwitch.isHidden = false
                toggleSwitch.isEnabled = isEnabled
                
                // Remove the selection view if the setting is disabled
                cellSelectedBackgroundView.isHidden = !isEnabled
                
                let newValue: Bool = Storage.shared[key]
                
                if newValue != toggleSwitch.isOn {
                    toggleSwitch.setOn(newValue, animated: true)
                }
                
            case .customToggle(let value, let isEnabled, _, _):
                toggleSwitch.isHidden = false
                toggleSwitch.isEnabled = isEnabled
                
                // Remove the selection view if the setting is disabled
                cellSelectedBackgroundView.isHidden = !isEnabled
                
                if value != toggleSwitch.isOn {
                    toggleSwitch.setOn(value, animated: true)
                }

            case .settingEnum(_, let value, _), .generalEnum(let value, _):
                dropDownStackView.isHidden = false
                dropDownLabel.text = value
                
            case .listSelection(let isSelected, let storedSelection, _, _):
                tickImageView.isHidden = (!isSelected() && !storedSelection)
                tickImageView.alpha = (!isSelected() && storedSelection ? 0.3 : 1)
                
            case .trigger(let showChevron, _):
                pushChevronImageView.isHidden = !showChevron
            
            case .push(let showChevron, let tintColor, _, _):
                titleLabel.themeTextColor = tintColor
                iconImageView.themeTintColor = tintColor
                pushChevronImageView.isHidden = !showChevron
                
            case .present(let tintColor, _):
                titleLabel.themeTextColor = tintColor
                iconImageView.themeTintColor = tintColor
            
            case .rightButtonAction(let title, _):
                rightActionButtonContainerView.isHidden = false
                rightActionButtonLabel.text = title
        }
    }
    
    public func update(isEditing: Bool, animated: Bool) {}
    
    // MARK: - Interaction
    
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        
        // If the 'cellSelectedBackgroundView' is hidden then there is no background so we
        // should update the titleLabel to indicate the highlighted state
        if cellSelectedBackgroundView.isHidden {
            titleLabel.alpha = (highlighted ? 0.8 : 1)
        }

        cellSelectedBackgroundView.alpha = (highlighted ? 1 : 0)
        rightActionButtonContainerView.themeBackgroundColor = (highlighted ?
            .solidButton_highlight :
            .solidButton_background
        )
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        
        // Note: When initially triggering a selection we will be coming from the highlighted
        // state but will have already set highlighted to false at this stage, as a result we
        // need to swap back into the "highlighted" state so we can properly unhighlight within
        // the "deselect" animation
        guard !selected else {
            rightActionButtonContainerView.themeBackgroundColor = .solidButton_highlight
            return
        }
        guard animated else {
            rightActionButtonContainerView.themeBackgroundColor = .solidButton_background
            return
        }
        
        UIView.animate(withDuration: 0.4) { [weak self] in
            self?.rightActionButtonContainerView.themeBackgroundColor = .solidButton_background
        }
    }
    
    @objc private func extraActionTapped() {
        onExtraAction?()
    }
}
