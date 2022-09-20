// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionUtilitiesKit

final class SeedReminderView: UIView {
    private static let progressBarThickness: CGFloat = 2
    
    private let hasContinueButton: Bool
    
    var title = NSAttributedString(string: "") { didSet { titleLabel.attributedText = title } }
    var subtitle = "" { didSet { subtitleLabel.text = subtitle } }
    var delegate: SeedReminderViewDelegate?
    
    // MARK: - Components
    
    private lazy var progressIndicatorView: UIProgressView = {
        let result = UIProgressView()
        result.progressViewStyle = .bar
        result.themeProgressTintColor = .primary
        result.themeBackgroundColor = .borderSeparator
        result.set(.height, to: SeedReminderView.progressBarThickness)
        
        return result
    }()
    
    lazy var titleLabel: UILabel = {
        let result = UILabel()
        result.font = .boldSystemFont(ofSize: Values.smallFontSize)
        result.themeTextColor = .textPrimary
        result.lineBreakMode = .byTruncatingTail
        
        return result
    }()
    
    lazy var subtitleLabel: UILabel = {
        let result = UILabel()
        result.font = .systemFont(ofSize: Values.verySmallFontSize)
        result.themeTextColor = .textSecondary
        result.lineBreakMode = .byWordWrapping
        result.numberOfLines = 2
        
        return result
    }()
    
    // MARK: - Lifecycle
    
    init(hasContinueButton: Bool) {
        self.hasContinueButton = hasContinueButton
        
        super.init(frame: CGRect.zero)
        
        setUpViewHierarchy()
    }
    
    override init(frame: CGRect) {
        preconditionFailure("Use init(hasContinueButton:) instead.")
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure("Use init(hasContinueButton:) instead.")
    }
    
    private func setUpViewHierarchy() {
        // Set background color
        themeBackgroundColor = .conversationButton_background
        
        // Note: We hard-code the height of the subtitle to 2 lines so changing it's content
        // doesn't result in the view changing height (which looks buggy)
        let subtitleContainerView: UIView = UIView()
        subtitleContainerView.set(.height, to: (subtitleLabel.font.lineHeight * 2))
        subtitleContainerView.addSubview(subtitleLabel)
        subtitleLabel.pin(.top, to: .top, of: subtitleContainerView)
        subtitleLabel.pin(.leading, to: .leading, of: subtitleContainerView)
        subtitleLabel.pin(.trailing, to: .trailing, of: subtitleContainerView)
        
        // Set up label stack view
        let labelStackView = UIStackView(arrangedSubviews: [ titleLabel, subtitleContainerView ])
        labelStackView.axis = .vertical
        labelStackView.spacing = 4
        
        // Set up button
        let button = OutlineButton(style: .regular, size: .small)
        button.setTitle("continue_2".localized(), for: UIControl.State.normal)
        button.set(.width, to: 96)
        button.addTarget(self, action: #selector(handleContinueButtonTapped), for: UIControl.Event.touchUpInside)
        
        // Set up content stack view
        let contentStackView = UIStackView(arrangedSubviews: [ labelStackView ])
        if hasContinueButton {
            contentStackView.addArrangedSubview(UIView.hStretchingSpacer())
            contentStackView.addArrangedSubview(button)
        }
        contentStackView.axis = .horizontal
        contentStackView.spacing = 4
        contentStackView.alignment = .center
        let horizontalSpacing = isIPhone5OrSmaller ? Values.smallSpacing : Values.mediumSpacing
        contentStackView.layoutMargins = UIEdgeInsets(top: 0, leading: horizontalSpacing + Values.accentLineThickness, bottom: 0, trailing: horizontalSpacing)
        contentStackView.isLayoutMarginsRelativeArrangement = true
        
        // Set up separator
        let separator = UIView()
        separator.set(.height, to: Values.separatorThickness)
        separator.themeBackgroundColor = .borderSeparator
        
        // Set up stack view
        let stackView = UIStackView(arrangedSubviews: [ progressIndicatorView, contentStackView, separator ])
        stackView.axis = .vertical
        stackView.spacing = isIPhone5OrSmaller ? Values.smallSpacing : Values.mediumSpacing
        addSubview(stackView)
        stackView.pin(to: self)
    }
    
    // MARK: - Updating
    
    func setProgress(_ progress: Float, animated isAnimated: Bool) {
        progressIndicatorView.setProgress(progress, animated: isAnimated)
    }
    
    @objc private func handleContinueButtonTapped() {
        delegate?.handleContinueButtonTapped(from: self)
    }
}

// MARK: Delegate
protocol SeedReminderViewDelegate {

    func handleContinueButtonTapped(from seedReminderView: SeedReminderView)
}
