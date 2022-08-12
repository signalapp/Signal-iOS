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
        
        scrollView.addSubview(themesTitleLabel)
        scrollView.addSubview(themesStackView)
        scrollView.addSubview(primaryColorTitleLabel)
        scrollView.addSubview(primaryColorPreviewStackView)
        scrollView.addSubview(primaryColorScrollView)
        scrollView.addSubview(nightModeTitleLabel)
        scrollView.addSubview(nightModeStackView)
        
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
        
        themesTitleLabel.pin(.top, to: .top, of: scrollView)
        themesTitleLabel.pin(.left, to: .left, of: scrollView, withInset: Values.largeSpacing)
        
        themesStackView.pin(.top, to: .bottom, of: themesTitleLabel, withInset: Values.mediumSpacing)
        themesStackView.pin(.left, to: .left, of: scrollView)
        themesStackView.set(.width, to: .width, of: scrollView)
        
        primaryColorTitleLabel.pin(.top, to: .bottom, of: themesStackView, withInset: Values.mediumSpacing)
        primaryColorTitleLabel.pin(.left, to: .left, of: scrollView, withInset: Values.largeSpacing)
        
        primaryColorPreviewStackView.pin(.top, to: .bottom, of: primaryColorTitleLabel, withInset: Values.smallSpacing)
        primaryColorPreviewStackView.pin(.left, to: .left, of: scrollView)
        primaryColorPreviewStackView.set(.width, to: .width, of: scrollView)
        
        primaryColorScrollView.pin(.top, to: .bottom, of: primaryColorPreviewStackView, withInset: Values.mediumSpacing)
        primaryColorScrollView.pin(.left, to: .left, of: scrollView)
        primaryColorScrollView.set(.width, to: .width, of: scrollView)
        
        primaryColorSelectionStackView.pin(to: primaryColorScrollView)
        primaryColorSelectionStackView.set(.height, to: .height, of: primaryColorScrollView)
        
        nightModeTitleLabel.pin(.top, to: .bottom, of: primaryColorScrollView, withInset: Values.largeSpacing)
        nightModeTitleLabel.pin(.left, to: .left, of: scrollView, withInset: Values.largeSpacing)
        nightModeTitleLabel.set(.width, to: .width, of: scrollView)
        
        nightModeStackView.pin(.top, to: .bottom, of: nightModeTitleLabel, withInset: Values.smallSpacing)
        nightModeStackView.pin(.bottom, to: .bottom, of: scrollView)
        nightModeStackView.pin(.left, to: .left, of: scrollView)
        nightModeStackView.set(.width, to: .width, of: scrollView)
        
        nightModeToggleLabel.setContentHuggingVerticalHigh()
        nightModeToggleLabel.setCompressionResistanceVerticalHigh()
        nightModeToggleLabel.center(.vertical, in: nightModeToggleView)
        nightModeToggleLabel.pin(.left, to: .left, of: nightModeToggleView, withInset: Values.largeSpacing)
        
        nightModeToggleSwitch.pin(.top, to: .top, of: nightModeToggleView, withInset: Values.smallSpacing)
        nightModeToggleSwitch.pin(.bottom, to: .bottom, of: nightModeToggleView, withInset: -Values.smallSpacing)
        nightModeToggleSwitch.pin(.right, to: .right, of: nightModeToggleView, withInset: -Values.largeSpacing)
    }
    
    // MARK: - Actions
    
    @objc private func nightModeToggleChanged(sender: UISwitch) {
        ThemeManager.matchSystemNightModeSetting = sender.isOn
    }
}
