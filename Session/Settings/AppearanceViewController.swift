// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SignalUtilitiesKit

final class AppearanceViewController: BaseVC {
    // MARK: - Components
    
    private let scrollView: UIScrollView = {
        let result: UIScrollView = UIScrollView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.showsVerticalScrollIndicator = false
        result.showsHorizontalScrollIndicator = false
        result.contentInset = UIEdgeInsets(
            top: 0,
            leading: 0,
            bottom: Values.largeSpacing,
            trailing: 0
        )
        
        return result
    }()
    
    private let contentView: UIView = UIView()
    
    private let themesTitleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.font = UIFont.systemFont(ofSize: Values.mediumFontSize, weight: .regular)
        result.themeTextColor = .textSecondary
        result.text = "APPEARANCE_THEMES_TITLE".localized()
        
        return result
    }()
    
    private let themesStackView: UIStackView = {
        let result: UIStackView = UIStackView()
        result.translatesAutoresizingMaskIntoConstraints = true
        result.axis = .vertical
        result.distribution = .equalCentering
        result.alignment = .fill
        
        return result
    }()
    
    private lazy var themeSelectionViews: [ThemeSelectionView] = Theme.allCases
        .map { theme in
            let result: ThemeSelectionView = ThemeSelectionView(theme: theme) { [weak self] theme in
                ThemeManager.currentTheme = theme
            }
            result.update(isSelected: (ThemeManager.currentTheme == theme))
            
            return result
        }
    
    private let primaryColorTitleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.font = UIFont.systemFont(ofSize: Values.mediumFontSize, weight: .regular)
        result.themeTextColor = .textSecondary
        result.text = "APPEARANCE_PRIMARY_COLOR_TITLE".localized()
        
        return result
    }()
    
    private let primaryColorPreviewStackView: UIStackView = {
        let result: UIStackView = UIStackView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.axis = .vertical
        result.distribution = .equalCentering
        result.alignment = .fill
        
        return result
    }()
    
    private let primaryColorPreviewView: ThemePreviewView = {
        let result: ThemePreviewView = ThemePreviewView()
        result.translatesAutoresizingMaskIntoConstraints = false
        
        return result
    }()
    
    private let primaryColorScrollView: UIScrollView = {
        let result: UIScrollView = UIScrollView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.showsVerticalScrollIndicator = false
        result.showsHorizontalScrollIndicator = false
        result.contentInset = UIEdgeInsets(
            top: 0,
            leading: Values.largeSpacing,
            bottom: 0,
            trailing: Values.largeSpacing
        )
        
        if CurrentAppContext().isRTL {
            result.transform = CGAffineTransform.identity.scaledBy(x: -1, y: 1)
        }
        
        return result
    }()
    
    private let primaryColorSelectionStackView: UIStackView = {
        let result: UIStackView = UIStackView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.axis = .horizontal
        result.distribution = .equalCentering
        result.alignment = .fill
        
        return result
    }()
    
    private lazy var primaryColorSelectionViews: [PrimaryColorSelectionView] = Theme.PrimaryColor.allCases
        .map { color in
            let result: PrimaryColorSelectionView = PrimaryColorSelectionView(color: color) { [weak self] color in
                ThemeManager.primaryColor = color
            }
            result.update(isSelected: (ThemeManager.primaryColor == color))
            
            return result
        }
    
    private let nightModeTitleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.font = UIFont.systemFont(ofSize: Values.mediumFontSize, weight: .regular)
        result.themeTextColor = .textSecondary
        result.text = "APPEARANCE_NIGHT_MODE_TITLE".localized()
        
        return result
    }()
    
    private let nightModeStackView: UIStackView = {
        let result: UIStackView = UIStackView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.axis = .vertical
        result.distribution = .equalCentering
        result.alignment = .fill
        
        return result
    }()
    
    private let nightModeToggleView: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.themeBackgroundColor = .appearance_sectionBackground
        
        return result
    }()
    
    private let nightModeToggleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.font = UIFont.systemFont(ofSize: Values.mediumFontSize, weight: .regular)
        result.themeTextColor = .textPrimary
        result.text = "APPEARANCE_NIGHT_MODE_TOGGLE".localized()
        
        return result
    }()
    
    private lazy var nightModeToggleSwitch: UISwitch = {
        let result: UISwitch = UISwitch()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.themeOnTintColor = .primary
        result.isOn = ThemeManager.matchSystemNightModeSetting
        result.addTarget(self, action: #selector(nightModeToggleChanged(sender:)), for: .valueChanged)
        
        return result
    }()
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        ViewControllerUtilities.setUpDefaultSessionStyle(
            for: self,
            title: "APPEARANCE_TITLE".localized(),
            hasCustomBackButton: false
        )
        
        view.themeBackgroundColor = .backgroundPrimary
        view.addSubview(scrollView)
        
        // Note: Need to add to a 'contentView' to ensure the automatic RTL behaviour
        // works properly (apparently it doesn't play nicely with UIScrollView internals)
        scrollView.addSubview(contentView)
        
        contentView.addSubview(themesTitleLabel)
        contentView.addSubview(themesStackView)
        contentView.addSubview(primaryColorTitleLabel)
        contentView.addSubview(primaryColorPreviewStackView)
        contentView.addSubview(primaryColorScrollView)
        contentView.addSubview(nightModeTitleLabel)
        contentView.addSubview(nightModeStackView)
        
        themesStackView.addArrangedSubview(UIView.separator())
        themeSelectionViews.forEach { view in
            themesStackView.addArrangedSubview(view)
            themesStackView.addArrangedSubview(UIView.separator())
        }
        
        primaryColorPreviewStackView.addArrangedSubview(UIView.separator())
        primaryColorPreviewStackView.addArrangedSubview(primaryColorPreviewView)
        primaryColorPreviewStackView.addArrangedSubview(UIView.separator())
        
        primaryColorScrollView.addSubview(primaryColorSelectionStackView)
        
        primaryColorSelectionViews.forEach { view in
            primaryColorSelectionStackView.addArrangedSubview(view)
        }
        
        nightModeStackView.addArrangedSubview(UIView.separator())
        nightModeStackView.addArrangedSubview(nightModeToggleView)
        nightModeStackView.addArrangedSubview(UIView.separator())
        
        nightModeToggleView.addSubview(nightModeToggleLabel)
        nightModeToggleView.addSubview(nightModeToggleSwitch)
        
        // Register an observer so when the theme changes the selected theme and primary colour
        // are both updated to match
        ThemeManager.onThemeChange(observer: self) { [weak self] theme, primaryColor in
            self?.themeSelectionViews.forEach { view in
                view.update(isSelected: (theme == view.theme))
            }
            
            self?.primaryColorSelectionViews.forEach { view in
                view.update(isSelected: (primaryColor == view.color))
            }
        }
        
        setupLayout()
    }
    
    private func setupLayout() {
        scrollView.pin(to: view)
        contentView.pin(to: scrollView)
        contentView.set(.width, to: .width, of: scrollView)
        
        themesTitleLabel.pin(.top, to: .top, of: contentView)
        themesTitleLabel.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        
        themesStackView.pin(.top, to: .bottom, of: themesTitleLabel, withInset: Values.mediumSpacing)
        themesStackView.pin(.leading, to: .leading, of: contentView)
        themesStackView.set(.width, to: .width, of: contentView)
        
        primaryColorTitleLabel.pin(.top, to: .bottom, of: themesStackView, withInset: Values.mediumSpacing)
        primaryColorTitleLabel.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        
        primaryColorPreviewStackView.pin(.top, to: .bottom, of: primaryColorTitleLabel, withInset: Values.smallSpacing)
        primaryColorPreviewStackView.pin(.leading, to: .leading, of: contentView)
        primaryColorPreviewStackView.set(.width, to: .width, of: contentView)
        
        primaryColorScrollView.pin(.top, to: .bottom, of: primaryColorPreviewStackView, withInset: Values.mediumSpacing)
        primaryColorScrollView.pin(.leading, to: .leading, of: contentView)
        primaryColorScrollView.set(.width, to: .width, of: contentView)
        
        primaryColorSelectionStackView.pin(to: primaryColorScrollView)
        primaryColorSelectionStackView.set(.height, to: .height, of: primaryColorScrollView)
        
        nightModeTitleLabel.pin(.top, to: .bottom, of: primaryColorScrollView, withInset: Values.largeSpacing)
        nightModeTitleLabel.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        nightModeTitleLabel.set(.width, to: .width, of: contentView, withOffset: -(Values.largeSpacing * 2))
        
        nightModeStackView.pin(.top, to: .bottom, of: nightModeTitleLabel, withInset: Values.smallSpacing)
        nightModeStackView.pin(.bottom, to: .bottom, of: contentView)
        nightModeStackView.pin(.leading, to: .leading, of: contentView)
        nightModeStackView.set(.width, to: .width, of: contentView)
        
        nightModeToggleLabel.setContentHuggingVerticalHigh()
        nightModeToggleLabel.setCompressionResistanceVerticalHigh()
        nightModeToggleLabel.center(.vertical, in: nightModeToggleView)
        nightModeToggleLabel.pin(.leading, to: .leading, of: nightModeToggleView, withInset: Values.largeSpacing)
        
        nightModeToggleSwitch.pin(.top, to: .top, of: nightModeToggleView, withInset: Values.smallSpacing)
        nightModeToggleSwitch.pin(.bottom, to: .bottom, of: nightModeToggleView, withInset: -Values.smallSpacing)
        nightModeToggleSwitch.pin(.trailing, to: .trailing, of: nightModeToggleView, withInset: -Values.largeSpacing)
    }
    
    // MARK: - Actions
    
    @objc private func nightModeToggleChanged(sender: UISwitch) {
        ThemeManager.matchSystemNightModeSetting = sender.isOn
    }
}
