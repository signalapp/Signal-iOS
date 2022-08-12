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
        result.setThemeBackgroundColor(.appearance_buttonHighlight, for: .highlighted)
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
    
    private let titleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isUserInteractionEnabled = false
        result.font = UIFont.systemFont(ofSize: Values.mediumFontSize, weight: .bold)
        result.themeTextColor = .textPrimary
        
        return result
    }()
    
    private let selectionBorderView: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isUserInteractionEnabled = false
        result.layer.borderWidth = 1
        result.layer.cornerRadius = (ThemeSelectionView.selectionBorderSize / 2)
        
        return result
    }()
    
    private let selectionView: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isUserInteractionEnabled = false
        result.layer.cornerRadius = (ThemeSelectionView.selectionSize / 2)
        
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
        previewView.backgroundColor = theme.colors[.backgroundPrimary]
        previewView.layer.borderColor = theme.colors[.borderSeparator]?.cgColor
        previewIncomingMessageView.backgroundColor = theme.colors[.messageBubble_incomingBackground]
        previewOutgoingMessageView.backgroundColor = theme.colors[.defaultPrimary]
        titleLabel.text = theme.title
        
        // Add the UI
        addSubview(backgroundButton)
        addSubview(previewView)
        addSubview(titleLabel)
        addSubview(selectionBorderView)
        addSubview(selectionView)
        
        previewView.addSubview(previewIncomingMessageView)
        previewView.addSubview(previewOutgoingMessageView)
        
        setupLayout()
    }
    
    private func setupLayout() {
        backgroundButton.pin(to: self)
        
        previewView.pin(.top, to: .top, of: self, withInset: Values.smallSpacing)
        previewView.pin(.left, to: .left, of: self, withInset: Values.largeSpacing)
        previewView.pin(.bottom, to: .bottom, of: self, withInset: -Values.smallSpacing)
        previewView.set(.width, to: 76)
        previewView.set(.height, to: 70)
        
        previewIncomingMessageView.bottomAnchor
            .constraint(equalTo: previewView.centerYAnchor, constant: -1)
            .isActive = true
        previewIncomingMessageView.pin(.left, to: .left, of: previewView, withInset: Values.smallSpacing)
        previewIncomingMessageView.set(.width, to: 40)
        previewIncomingMessageView.set(.height, to: 12)
        
        previewOutgoingMessageView.topAnchor
            .constraint(equalTo: previewView.centerYAnchor, constant: 1)
            .isActive = true
        previewOutgoingMessageView.pin(.right, to: .right, of: previewView, withInset: -Values.smallSpacing)
        previewOutgoingMessageView.set(.width, to: 40)
        previewOutgoingMessageView.set(.height, to: 12)
        
        titleLabel.center(.vertical, in: self)
        titleLabel.pin(.left, to: .right, of: previewView, withInset: Values.mediumSpacing)
        
        selectionBorderView.center(.vertical, in: self)
        selectionBorderView.pin(.right, to: .right, of: self, withInset: -Values.veryLargeSpacing)
        selectionBorderView.set(.width, to: ThemeSelectionView.selectionBorderSize)
        selectionBorderView.set(.height, to: ThemeSelectionView.selectionBorderSize)
        
        selectionView.center(in: selectionBorderView)
        selectionView.set(.width, to: ThemeSelectionView.selectionSize)
        selectionView.set(.height, to: ThemeSelectionView.selectionSize)
    }
    
    // MARK: - Content
    
    func update(isSelected: Bool) {
        selectionBorderView.themeBorderColor = (isSelected ?
            .radioButton_selectedBorder :
            .radioButton_unselectedBorder
        )
        selectionView.themeBackgroundColor = (isSelected ?
            .radioButton_selectedBackground :
            .radioButton_unselectedBackground
        )
    }
    
    @objc func itemSelected() {
        onSelected(theme)
    }
}
