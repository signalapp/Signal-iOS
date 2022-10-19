// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

class ThemeSelectionView: UIView {
    private static let selectionBorderSize: CGFloat = 26
    private static let selectionSize: CGFloat = 20
    
    public let theme: Theme
    private let onSelected: (Theme) -> ()
    
    // MARK: - Components
    
    private lazy var backgroundButton: UIButton = {
        let result: UIButton = UIButton()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.setThemeBackgroundColor(.appearance_buttonBackground, for: .normal)
        result.setThemeBackgroundColor(.highlighted(.appearance_buttonBackground), for: .highlighted)
        result.addTarget(self, action: #selector(itemSelected), for: .touchUpInside)
        
        return result
    }()
    
    private let previewView: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isUserInteractionEnabled = false
        result.layer.cornerRadius = 6
        result.layer.borderWidth = 1
        
        return result
    }()
    
    private let previewIncomingMessageView: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isUserInteractionEnabled = false
        result.layer.cornerRadius = 6
        
        return result
    }()
    
    private let previewOutgoingMessageView: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isUserInteractionEnabled = false
        result.layer.cornerRadius = 6
        
        return result
    }()
    
    private let selectionView: RadioButton = {
        let result: RadioButton = RadioButton(size: .medium)
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isUserInteractionEnabled = false
        result.font = .systemFont(ofSize: Values.mediumFontSize, weight: .bold)
        
        return result
    }()
    
    // MARK: - Initializtion
    
    init(theme: Theme, onSelected: @escaping (Theme) -> ()) {
        self.theme = theme
        self.onSelected = onSelected
        
        super.init(frame: .zero)
        
        setupUI(theme: theme)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Use init(theme:) instead")
    }
    
    // MARK: - Layout
    
    private func setupUI(theme: Theme) {
        self.themeBackgroundColor = .appearance_sectionBackground
        
        // Set the appropriate colours
        previewView.themeBackgroundColorForced = .theme(theme, color: .backgroundPrimary)
        previewView.themeBorderColorForced = .theme(theme, color: .borderSeparator)
        previewIncomingMessageView.themeBackgroundColorForced = .theme(theme, color: .messageBubble_incomingBackground)
        previewOutgoingMessageView.themeBackgroundColorForced = .theme(theme, color: .defaultPrimary)
        selectionView.text = theme.title
        
        // Add the UI
        addSubview(backgroundButton)
        addSubview(previewView)
        addSubview(selectionView)
        
        previewView.addSubview(previewIncomingMessageView)
        previewView.addSubview(previewOutgoingMessageView)
        
        setupLayout()
    }
    
    private func setupLayout() {
        backgroundButton.pin(to: self)
        
        previewView.pin(.top, to: .top, of: self, withInset: Values.smallSpacing)
        previewView.pin(.leading, to: .leading, of: self, withInset: Values.largeSpacing)
        previewView.pin(.bottom, to: .bottom, of: self, withInset: -Values.smallSpacing)
        previewView.set(.width, to: 76)
        previewView.set(.height, to: 70)
        
        previewIncomingMessageView.bottomAnchor
            .constraint(equalTo: previewView.centerYAnchor, constant: -1)
            .isActive = true
        previewIncomingMessageView.pin(.leading, to: .leading, of: previewView, withInset: Values.smallSpacing)
        previewIncomingMessageView.set(.width, to: 40)
        previewIncomingMessageView.set(.height, to: 12)
        
        previewOutgoingMessageView.topAnchor
            .constraint(equalTo: previewView.centerYAnchor, constant: 1)
            .isActive = true
        previewOutgoingMessageView.pin(.trailing, to: .trailing, of: previewView, withInset: -Values.smallSpacing)
        previewOutgoingMessageView.set(.width, to: 40)
        previewOutgoingMessageView.set(.height, to: 12)
        
        selectionView.center(.vertical, in: self)
        selectionView.pin(.leading, to: .trailing, of: previewView, withInset: Values.mediumSpacing)
        selectionView.pin(.trailing, to: .trailing, of: self, withInset: -Values.veryLargeSpacing)
    }
    
    // MARK: - Content
    
    func update(isSelected: Bool) {
        selectionView.update(isSelected: isSelected)
    }
    
    @objc func itemSelected() {
        onSelected(theme)
    }
}
