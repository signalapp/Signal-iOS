// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

// FIXME: Remove this and use the 'SessionCell' instead
public class RadioButton: UIView {
    private static let selectionBorderSize: CGFloat = 26
    private static let selectionSize: CGFloat = 20
    
    public enum Size {
        case small
        case medium
        
        var borderSize: CGFloat {
            switch self {
                case .small: return 20
                case .medium: return 26
            }
        }
        
        var selectionSize: CGFloat {
            switch self {
                case .small: return 15
                case .medium: return 20
            }
        }
    }
    
    public var font: UIFont {
        get { titleLabel.font }
        set { titleLabel.font = newValue }
    }
    
    public var text: String? {
        get { titleLabel.text }
        set { titleLabel.text = newValue }
    }
    
    public private(set) var isSelected: Bool = false
    private let onSelected: ((RadioButton) -> ())?
    
    // MARK: - UI
    
    private lazy var selectionButton: UIButton = {
        let result: UIButton = UIButton()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.addTarget(self, action: #selector(itemSelected), for: .touchUpInside)
        
        return result
    }()
    
    private let titleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isUserInteractionEnabled = false
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.themeTextColor = .textPrimary
        result.numberOfLines = 0
        
        return result
    }()
    
    private let selectionBorderView: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isUserInteractionEnabled = false
        result.layer.borderWidth = 1
        result.themeBorderColor = .radioButton_unselectedBorder
        
        return result
    }()
    
    private let selectionView: UIView = {
        let result: UIView = UIView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.isUserInteractionEnabled = false
        result.themeBackgroundColor = .radioButton_unselectedBackground
        
        return result
    }()
    
    // MARK: - Initialization
    
    public init(size: Size, onSelected: ((RadioButton) -> ())? = nil) {
        self.onSelected = onSelected
        
        super.init(frame: .zero)
        
        setupViewHierarchy(size: size)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Layout
    
    private func setupViewHierarchy(size: Size) {
        addSubview(selectionButton)
        addSubview(titleLabel)
        addSubview(selectionBorderView)
        addSubview(selectionView)
        
        self.heightAnchor.constraint(
            greaterThanOrEqualTo: titleLabel.heightAnchor,
            constant: Values.mediumSpacing
        ).isActive = true
        self.heightAnchor.constraint(
            greaterThanOrEqualTo: selectionBorderView.heightAnchor,
            constant: Values.mediumSpacing
        ).isActive = true
        
        selectionButton.pin(to: self)
        
        titleLabel.center(.vertical, in: self)
        titleLabel.pin(.leading, to: .leading, of: self)
        
        selectionBorderView.center(.vertical, in: self)
        selectionBorderView.pin(.trailing, to: .trailing, of: self)
        selectionBorderView.set(.width, to: size.borderSize)
        selectionBorderView.set(.height, to: size.borderSize)
        
        selectionView.center(in: selectionBorderView)
        selectionView.set(.width, to: size.selectionSize)
        selectionView.set(.height, to: size.selectionSize)
        
        selectionBorderView.layer.cornerRadius = (size.borderSize / 2)
        selectionView.layer.cornerRadius = (size.selectionSize / 2)
    }
    
    // MARK: - Content
    
    public func setThemeBackgroundColor(_ value: ThemeValue, for state: UIControl.State) {
        selectionButton.setThemeBackgroundColor(value, for: state)
    }
    
    public func update(isSelected: Bool) {
        self.isSelected = isSelected
        
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
        onSelected?(self)
    }
}
