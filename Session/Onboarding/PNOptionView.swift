// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

final class OptionView: UIView {
    private let title: String
    private let explanation: String
    private let delegate: OptionViewDelegate
    private let isRecommended: Bool
    
    var isSelected = false { didSet { handleIsSelectedChanged() } }

    private static let cornerRadius: CGFloat = 8
    
    init(title: String, explanation: String, delegate: OptionViewDelegate, isRecommended: Bool = false) {
        self.title = title
        self.explanation = explanation
        self.delegate = delegate
        self.isRecommended = isRecommended
        
        super.init(frame: CGRect.zero)
        
        setUpViewHierarchy()
    }

    override init(frame: CGRect) {
        preconditionFailure("Use init(string:explanation:) instead.")
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(string:explanation:) instead.")
    }

    private func setUpViewHierarchy() {
        themeBackgroundColor = .backgroundSecondary
        
        // Round corners
        layer.cornerRadius = OptionView.cornerRadius
        
        // Set up border
        themeBorderColor = .borderSeparator
        layer.borderWidth = 1
        
        // Set up shadow
        themeShadowColor = .black
        layer.shadowOffset = CGSize(width: 0, height: 0.8)
        
        ThemeManager.onThemeChange(observer: self) { [weak self] theme, _ in
            switch theme.interfaceStyle {
                case .light:
                    self?.layer.shadowOpacity = 0.16
                    self?.layer.shadowRadius = 4
                    
                default:
                    self?.layer.shadowOpacity = 1
                    self?.layer.shadowRadius = 6
            }
        }
        
        // Set up title label
        let titleLabel: UILabel = UILabel()
        titleLabel.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        titleLabel.text = title
        titleLabel.themeTextColor = .textPrimary
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.numberOfLines = 0
        
        // Set up explanation label
        let explanationLabel: UILabel = UILabel()
        explanationLabel.font = .systemFont(ofSize: Values.verySmallFontSize)
        explanationLabel.text = explanation
        explanationLabel.themeTextColor = .textPrimary
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.numberOfLines = 0
        
        // Set up stack view
        let stackView = UIStackView(arrangedSubviews: [ titleLabel, explanationLabel ])
        stackView.axis = .vertical
        stackView.spacing = 4
        stackView.alignment = .fill
        addSubview(stackView)
        
        stackView.pin(.leading, to: .leading, of: self, withInset: 12)
        stackView.pin(.top, to: .top, of: self, withInset: 12)
        self.pin(.trailing, to: .trailing, of: stackView, withInset: 12)
        self.pin(.bottom, to: .bottom, of: stackView, withInset: 12)
        
        // Set up recommended label if needed
        if isRecommended {
            let recommendedLabel: UILabel = UILabel()
            recommendedLabel.font = .boldSystemFont(ofSize: Values.smallFontSize)
            recommendedLabel.text = "vc_pn_mode_recommended_option_tag".localized()
            recommendedLabel.themeTextColor = .primary
            stackView.addArrangedSubview(recommendedLabel)
        }
        
        // Set up tap gesture recognizer
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGestureRecognizer)
    }

    @objc private func handleTap() {
        isSelected = !isSelected
    }

    private func handleIsSelectedChanged() {
        UIView.animate(withDuration: 0.3) { [weak self] in
            self?.themeBorderColor = (self?.isSelected == true ? .primary : .borderSeparator)
            self?.themeShadowColor = (self?.isSelected == true ? .primary : .black)
        }
        
        // Notify delegate
        if isSelected { delegate.optionViewDidActivate(self) }
    }
}

// MARK: - Option View Delegate

protocol OptionViewDelegate {
    func optionViewDidActivate(_ optionView: OptionView)
}
