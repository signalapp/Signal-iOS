// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

class PrimaryColorSelectionView: UIView {
    private static let selectionBorderSize: CGFloat = 36
    private static let selectionSize: CGFloat = 30
    
    public let color: Theme.PrimaryColor
    private let onSelected: (Theme.PrimaryColor) -> ()
    
    // MARK: - Components
    
    private lazy var backgroundButton: UIButton = {
        let result: UIButton = UIButton()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.addTarget(self, action: #selector(itemSelected), for: .touchUpInside)
        
        return result
    }()
    
    private let selectionBorderView: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isUserInteractionEnabled = false
        result.themeBorderColor = .radioButton_selectedBorder
        result.layer.borderWidth = 1
        result.layer.cornerRadius = (PrimaryColorSelectionView.selectionBorderSize / 2)
        result.isHidden = true
        
        return result
    }()
    
    private let selectionView: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isUserInteractionEnabled = false
        result.layer.cornerRadius = (PrimaryColorSelectionView.selectionSize / 2)
        
        return result
    }()
    
    // MARK: - Initializtion
    
    init(color: Theme.PrimaryColor, onSelected: @escaping (Theme.PrimaryColor) -> ()) {
        self.color = color
        self.onSelected = onSelected
        
        super.init(frame: .zero)
        
        setupUI(color: color)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Use init(color:) instead")
    }
    
    // MARK: - Layout
    
    private func setupUI(color: Theme.PrimaryColor) {
        // Set the appropriate colours
        selectionView.themeBackgroundColorForced = .primary(color)
        
        // Add the UI
        addSubview(backgroundButton)
        addSubview(selectionBorderView)
        addSubview(selectionView)
        
        setupLayout()
    }
    
    private func setupLayout() {
        backgroundButton.pin(to: self)
        
        selectionBorderView.pin(to: self)
        selectionBorderView.set(.width, to: PrimaryColorSelectionView.selectionBorderSize)
        selectionBorderView.set(.height, to: PrimaryColorSelectionView.selectionBorderSize)
        
        selectionView.center(in: selectionBorderView)
        selectionView.set(.width, to: PrimaryColorSelectionView.selectionSize)
        selectionView.set(.height, to: PrimaryColorSelectionView.selectionSize)
    }
    
    // MARK: - Content
    
    func update(isSelected: Bool) {
        selectionBorderView.isHidden = !isSelected
    }
    
    @objc func itemSelected() {
        onSelected(color)
    }
}
