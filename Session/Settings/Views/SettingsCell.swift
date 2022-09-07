// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import SessionUIKit

class SettingsCell: UITableViewCell {
    /// This value is here to allow the theming update callback to be released when preparing for reuse
    private var instanceView: UIView = UIView()
    private var subtitleExtraView: UIView?
    private var onExtraAction: (() -> Void)?
    
    // MARK: - UI
    
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
        result.layoutMargins = UIEdgeInsets(
            top: Values.mediumSpacing,
            leading: Values.largeSpacing,
            bottom: Values.mediumSpacing,
            trailing: Values.largeSpacing
        )
        
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
        
        return result
    }()
    
    private let titleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.themeTextColor = .textPrimary
        result.numberOfLines = 0
        
        return result
    }()
    
    private let subtitleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.themeTextColor = .textPrimary
        result.numberOfLines = 0
        result.isHidden = true
        
        return result
    }()
    
    private lazy var extraActionButton: UIButton = {
        let result: UIButton = UIButton()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.titleLabel?.font = .boldSystemFont(ofSize: Values.smallFontSize)
        result.contentHorizontalAlignment = .left
        result.contentEdgeInsets = UIEdgeInsets(
            top: 8,
            left: 0,
            bottom: 0,
            right: 0
        )
        result.addTarget(self, action: #selector(extraActionTapped), for: .touchUpInside)
        result.isHidden = true
        
        return result
    }()
    
    private let actionContainerView: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isHidden = true
        
        return result
    }()
    
    private let pushChevronImageView: UIImageView = {
        let result: UIImageView = UIImageView(image: UIImage(systemName: "chevron.right"))
        result.translatesAutoresizingMaskIntoConstraints = false
        result.themeTintColor = .textPrimary
        result.isHidden = true
        
        return result
    }()
    
    private let toggleSwitch: UISwitch = {
        let result: UISwitch = UISwitch()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isUserInteractionEnabled = false // Triggered by didSelectCell instead
        result.themeOnTintColor = .primary
        result.isHidden = true
        
        return result
    }()
    
    private let dropDownImageView: UIImageView = {
        let result: UIImageView = UIImageView(image: UIImage(systemName: "arrowtriangle.down.fill"))
        result.translatesAutoresizingMaskIntoConstraints = false
        result.themeTintColor = .textPrimary
        result.isHidden = true
        
        return result
    }()
    
    private let dropDownLabel: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.font = .systemFont(ofSize: Values.smallFontSize, weight: .medium)
        result.themeTextColor = .textPrimary
        result.isHidden = true
        
        return result
    }()
    
    private let tickImageView: UIImageView = {
        let result: UIImageView = UIImageView(image: UIImage(systemName: "checkmark"))
        result.translatesAutoresizingMaskIntoConstraints = false
        result.themeTintColor = .primary
        result.isHidden = true
        
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
        contentView.addSubview(topSeparator)
        contentView.addSubview(contentStackView)
        contentView.addSubview(botSeparator)
        
        contentStackView.addArrangedSubview(iconImageView)
        contentStackView.addArrangedSubview(titleStackView)
        contentStackView.addArrangedSubview(actionContainerView)
        contentStackView.addArrangedSubview(pushChevronImageView)
        contentStackView.addArrangedSubview(toggleSwitch)
        contentStackView.addArrangedSubview(tickImageView)
        
        titleStackView.addArrangedSubview(titleLabel)
        titleStackView.addArrangedSubview(subtitleLabel)
        titleStackView.addArrangedSubview(extraActionButton)
        
        actionContainerView.addSubview(dropDownImageView)
        actionContainerView.addSubview(dropDownLabel)
        actionContainerView.addSubview(rightActionButtonContainerView)
        
        rightActionButtonContainerView.addSubview(rightActionButtonLabel)
        
        setupLayout()
    }
    
    private func setupLayout() {
        topSeparator.pin(.top, to: .top, of: contentView)
        topSeparator.pin(.left, to: .left, of: contentView)
        topSeparator.pin(.right, to: .right, of: contentView)
        
        contentStackView.pin(to: contentView)
        
        titleLabel.setCompressionResistanceHorizontalLow()
        subtitleLabel.setCompressionResistanceHorizontalLow()
        
        iconImageView.set(.width, to: 24)
        iconImageView.set(.height, to: 24)
        
        pushChevronImageView.setContentHuggingHigh()
        pushChevronImageView.setCompressionResistanceHigh()
        
        toggleSwitch.setContentHuggingHigh()
        toggleSwitch.setCompressionResistanceHigh()
        
        tickImageView.setContentHuggingHigh()
        tickImageView.setCompressionResistanceHigh()
        
        actionContainerView.setContentHuggingHigh()
        actionContainerView.setCompressionResistanceHigh()
        actionContainerView.set(.height, to: .height, of: contentStackView)
        
        dropDownImageView.center(.vertical, in: actionContainerView)
        dropDownImageView.pin(.left, to: .left, of: actionContainerView)
        dropDownImageView.set(.width, to: 10)
        dropDownImageView.set(.height, to: 10)
        
        dropDownLabel.setContentHuggingHigh()
        dropDownLabel.setCompressionResistanceHigh()
        dropDownLabel.center(.vertical, in: actionContainerView)
        dropDownLabel.pin(.left, to: .right, of: dropDownImageView, withInset: Values.verySmallSpacing)
        dropDownLabel.pin(.right, to: .right, of: actionContainerView)
        
        rightActionButtonContainerView.center(.vertical, in: actionContainerView)
        rightActionButtonContainerView.pin(.left, to: .left, of: actionContainerView)
        rightActionButtonContainerView.pin(.right, to: .right, of: actionContainerView)
        
        rightActionButtonLabel.setContentHuggingHigh()
        rightActionButtonLabel.setCompressionResistanceHigh()
        rightActionButtonLabel.pin(to: rightActionButtonContainerView, withInset: Values.smallSpacing)
        
        botSeparator.pin(.left, to: .left, of: contentView)
        botSeparator.pin(.right, to: .right, of: contentView)
        botSeparator.pin(.bottom, to: .bottom, of: contentView)
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
        
        self.themeBackgroundColor = nil
        self.selectedBackgroundView = nil
        self.instanceView = UIView()
        self.onExtraAction = nil
        self.accessibilityIdentifier = nil
        
        iconImageView.image = nil
        titleLabel.text = ""
        titleLabel.themeTextColor = .textPrimary
        subtitleLabel.text = ""
        dropDownLabel.text = ""
        
        topSeparator.isHidden = true
        iconImageView.isHidden = true
        subtitleLabel.isHidden = true
        extraActionButton.isHidden = true
        actionContainerView.isHidden = true
        pushChevronImageView.isHidden = true
        toggleSwitch.isHidden = true
        dropDownImageView.isHidden = true
        dropDownLabel.isHidden = true
        tickImageView.isHidden = true
        tickImageView.alpha = 1
        rightActionButtonContainerView.isHidden = true
        botSeparator.isHidden = true
        
        subtitleExtraView?.removeFromSuperview()
        subtitleExtraView = nil
    }
    
    public func update(
        icon: UIImage?,
        title: String,
        subtitle: String?,
        alignment: NSTextAlignment,
        accessibilityIdentifier: String?,
        subtitleExtraViewGenerator: (() -> UIView)?,
        action: SettingsAction,
        extraActionTitle: ((Theme, Theme.PrimaryColor) -> NSAttributedString)?,
        onExtraAction: (() -> Void)?,
        isFirstInSection: Bool,
        isLastInSection: Bool
    ) {
        self.instanceView = UIView()
        self.subtitleExtraView = subtitleExtraViewGenerator?()
        self.onExtraAction = onExtraAction
        self.accessibilityIdentifier = accessibilityIdentifier
        
        // Left content
        iconImageView.image = icon
        iconImageView.isHidden = (icon == nil)
        titleLabel.text = title
        titleLabel.textAlignment = alignment
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = (subtitle == nil)
        extraActionButton.isHidden = (extraActionTitle == nil)
        
        // Separator/background Visibility
        if action.shouldHaveBackground {
            self.themeBackgroundColor = .settings_tabBackground
            
            topSeparator.isHidden = isFirstInSection
            botSeparator.isHidden = !isLastInSection
        }
        else {
            self.themeBackgroundColor = nil
            
            topSeparator.isHidden = true
            botSeparator.isHidden = true
        }
        
        // Highlight
        let selectedBackgroundView = UIView()
        selectedBackgroundView.themeBackgroundColor = .settings_tabHighlight
        self.selectedBackgroundView = selectedBackgroundView
        
        // Action Behaviours
        switch action {
            case .threadInfo: break
            
            case .userDefaultsBool(let defaults, let key, let isEnabled, _):
                toggleSwitch.isHidden = false
                toggleSwitch.isEnabled = isEnabled
                
                // Remove the selection view if the setting is disabled
                if !isEnabled {
                    self.selectedBackgroundView = UIView()
                }
                
                let newValue: Bool = defaults.bool(forKey: key)
                
                if newValue != toggleSwitch.isOn {
                    toggleSwitch.setOn(newValue, animated: true)
                }
            
            case .settingBool(let key, _, let isEnabled):
                toggleSwitch.isHidden = false
                toggleSwitch.isEnabled = isEnabled
                
                // Remove the selection view if the setting is disabled
                if !isEnabled {
                    self.selectedBackgroundView = UIView()
                }
                
                let newValue: Bool = Storage.shared[key]
                
                if newValue != toggleSwitch.isOn {
                    toggleSwitch.setOn(newValue, animated: true)
                }
                
            case .customToggle(let value, let isEnabled, _, _):
                toggleSwitch.isHidden = false
                toggleSwitch.isEnabled = isEnabled
                
                // Remove the selection view if the setting is disabled
                if !isEnabled {
                    self.selectedBackgroundView = UIView()
                }
                
                if value != toggleSwitch.isOn {
                    toggleSwitch.setOn(value, animated: true)
                }

            case .settingEnum(_, let value, _), .generalEnum(let value, _):
                actionContainerView.isHidden = false
                dropDownImageView.isHidden = false
                dropDownLabel.isHidden = false
                dropDownLabel.text = value
                
            case .listSelection(let isSelected, let storedSelection, _, _):
                tickImageView.isHidden = (!isSelected() && !storedSelection)
                tickImageView.alpha = (!isSelected() && storedSelection ? 0.3 : 1)
                
            case .trigger(let showChevron, _):
                pushChevronImageView.isHidden = !showChevron
            
            case .push(let showChevron, let textColor, _, _):
                titleLabel.themeTextColor = textColor
                pushChevronImageView.isHidden = !showChevron
                
            case .present(_): break
            
            case .rightButtonAction(let title, _):
                actionContainerView.isHidden = false
                rightActionButtonContainerView.isHidden = false
                rightActionButtonLabel.text = title
        }
        
        // Extra action
        if let extraActionTitle: ((Theme, Theme.PrimaryColor) -> NSAttributedString) = extraActionTitle {
            ThemeManager.onThemeChange(observer: instanceView) { [weak extraActionButton] theme, primaryColor in
                extraActionButton?.setAttributedTitle(
                    extraActionTitle(theme, primaryColor),
                    for: .normal
                )
            }
        }
    }
    
    public func update(isEditing: Bool, animated: Bool) {}
    
    // MARK: - Interaction
    
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)

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
