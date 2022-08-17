// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import GRDB
import SessionUIKit

class SettingsCell: UITableViewCell {
    /// This value is here to allow the theming update callback to be released when preparing for reuse
    private var instanceView: UIView = UIView()
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
        result.distribution = .equalSpacing
        result.alignment = .fill
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
    
    private lazy var rightActionButtonContainerView: UIView = {
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
        themeBackgroundColor = .settings_tabBackground
        
        // Highlight color
        let selectedBackgroundView = UIView()
        selectedBackgroundView.themeBackgroundColor = .settings_tabHighlight
        self.selectedBackgroundView = selectedBackgroundView
        
        contentView.addSubview(topSeparator)
        contentView.addSubview(contentStackView)
        contentView.addSubview(botSeparator)
        
        contentStackView.addArrangedSubview(titleStackView)
        contentStackView.addArrangedSubview(actionContainerView)
        
        titleStackView.addArrangedSubview(titleLabel)
        titleStackView.addArrangedSubview(subtitleLabel)
        titleStackView.addArrangedSubview(extraActionButton)
        
        actionContainerView.addSubview(pushChevronImageView)
        actionContainerView.addSubview(toggleSwitch)
        actionContainerView.addSubview(dropDownImageView)
        actionContainerView.addSubview(dropDownLabel)
        actionContainerView.addSubview(tickImageView)
        actionContainerView.addSubview(rightActionButtonContainerView)
        
        rightActionButtonContainerView.addSubview(rightActionButtonLabel)
        
        setupLayout()
    }
    
    private func setupLayout() {
        topSeparator.pin(.top, to: .top, of: contentView)
        topSeparator.pin(.left, to: .left, of: contentView)
        topSeparator.pin(.right, to: .right, of: contentView)
        
        contentStackView.pin(to: contentView)
        
        pushChevronImageView.center(.vertical, in: actionContainerView)
        pushChevronImageView.pin(.right, to: .right, of: actionContainerView)
        
        actionContainerView.widthAnchor
            .constraint(greaterThanOrEqualTo: toggleSwitch.widthAnchor)
            .isActive = true
        toggleSwitch.setCompressionResistanceHigh()
        toggleSwitch.center(.vertical, in: actionContainerView)
        toggleSwitch.pin(.right, to: .right, of: actionContainerView)
        
        dropDownLabel.setCompressionResistanceHigh()
        dropDownLabel.center(.vertical, in: actionContainerView)
        dropDownLabel.pin(.right, to: .right, of: actionContainerView)
        
        dropDownImageView.center(.vertical, in: actionContainerView)
        dropDownImageView.pin(.left, to: .left, of: actionContainerView)
        dropDownImageView.pin(.right, to: .left, of: dropDownLabel, withInset: -Values.verySmallSpacing)
        dropDownImageView.set(.width, to: 10)
        dropDownImageView.set(.height, to: 10)
        
        tickImageView.center(.vertical, in: actionContainerView)
        tickImageView.pin(.right, to: .right, of: actionContainerView)
        
        rightActionButtonContainerView.center(.vertical, in: actionContainerView)
        rightActionButtonContainerView.pin(.left, to: .left, of: actionContainerView)
        rightActionButtonContainerView.pin(.right, to: .right, of: actionContainerView)
        
        rightActionButtonLabel.setCompressionResistanceHigh()
        rightActionButtonLabel.pin(to: rightActionButtonContainerView, withInset: Values.smallSpacing)
        
        botSeparator.pin(.left, to: .left, of: contentView)
        botSeparator.pin(.right, to: .right, of: contentView)
        botSeparator.pin(.bottom, to: .bottom, of: contentView)
    }
    
    // MARK: - Content
    
    override func prepareForReuse() {
        super.prepareForReuse()
        
        self.instanceView = UIView()
        self.onExtraAction = nil
        
        titleLabel.text = ""
        titleLabel.themeTextColor = .textPrimary
        subtitleLabel.text = ""
        dropDownLabel.text = ""
        
        topSeparator.isHidden = true
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
    }
    
    public func update(
        title: String,
        subtitle: String?,
        action: SettingsAction,
        extraActionTitle: ((Theme, Theme.PrimaryColor) -> NSAttributedString)?,
        onExtraAction: (() -> Void)?,
        isFirstInSection: Bool,
        isLastInSection: Bool
    ) {
        self.instanceView = UIView()
        self.onExtraAction = onExtraAction
        
        // Left content
        titleLabel.text = title
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = (subtitle == nil)
        extraActionButton.isHidden = (extraActionTitle == nil)
        
        // Separator Visibility
        switch action {
            case .dangerPush:
                topSeparator.isHidden = true
                botSeparator.isHidden = true
                
            default:
                topSeparator.isHidden = isFirstInSection
                botSeparator.isHidden = !isLastInSection
        }
        
        // Action Behaviours
        switch action {
            case .userDefaultsBool(let defaults, let key, _):
                actionContainerView.isHidden = false
                toggleSwitch.isHidden = false
                
                let newValue: Bool = defaults.bool(forKey: key)
                
                if newValue != toggleSwitch.isOn {
                    toggleSwitch.setOn(newValue, animated: true)
                }
            
            case .settingBool(let key):
                actionContainerView.isHidden = false
                toggleSwitch.isHidden = false
                
                let newValue: Bool = Storage.shared[key]
                
                if newValue != toggleSwitch.isOn {
                    toggleSwitch.setOn(newValue, animated: true)
                }

            case .settingEnum(_, let value, _):
                actionContainerView.isHidden = false
                dropDownImageView.isHidden = false
                dropDownLabel.isHidden = false
                dropDownLabel.text = value
                
            case .listSelection(let isSelected, let storedSelection, _, _):
                actionContainerView.isHidden = false
                tickImageView.isHidden = (!isSelected() && !storedSelection)
                tickImageView.alpha = (!isSelected() && storedSelection ? 0.3 : 1)
                
            case .trigger, .push:
                actionContainerView.isHidden = false
                pushChevronImageView.isHidden = false
                
            case .dangerPush:
                titleLabel.themeTextColor = .danger
                actionContainerView.isHidden = false
            
            case .rightButtonModal(let title, _):
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
    
    // MARK: - Interaction
    
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)

        // Note: Only setting the highlighted state is done here, the unhighlight is done
        // in 'setSelected'
        guard highlighted else { return }
        
        rightActionButtonContainerView.themeBackgroundColor = .solidButton_highlight
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        
        // Note: Only un-setting the unhighlighted state is done here, the highlighted state is done
        // in 'setHighlighted'
        guard !selected else { return }
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
