// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

public final class Separator: UIView {
    private static let height: CGFloat = 24
    
    // MARK: - Components
    
    private let leftLine: UIView = {
        let result: UIView = UIView()
        result.themeBackgroundColor = .textSecondary
        result.set(.height, to: Values.separatorThickness)
        
        return result
    }()
    
    private let roundedLine: UIView = {
        let result: UIView = UIView()
        result.themeBorderColor = .textSecondary
        result.layer.borderWidth = Values.separatorThickness
        
        return result
    }()
    
    private lazy var titleLabel: UILabel = {
        let result = UILabel()
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.themeTextColor = .textSecondary
        result.textAlignment = .center
        
        return result
    }()
    
    private let rightLine: UIView = {
        let result: UIView = UIView()
        result.themeBackgroundColor = .textSecondary
        result.set(.height, to: Values.separatorThickness)
        
        return result
    }()
    
    // MARK: - Initialization
    
    public init(title: String? = nil) {
        super.init(frame: CGRect.zero)
        
        setUpViewHierarchy(title: title)
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        
        setUpViewHierarchy(title: nil)
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        setUpViewHierarchy(title: nil)
    }
    
    private func setUpViewHierarchy(title: String?) {
        titleLabel.text = title
        
        addSubview(leftLine)
        addSubview(roundedLine)
        addSubview(rightLine)
        addSubview(titleLabel)
        
        titleLabel.center(.horizontal, in: self)
        titleLabel.center(.vertical, in: self)
        roundedLine.pin(.top, to: .top, of: self)
        roundedLine.pin(.top, to: .top, of: titleLabel, withInset: -6)
        roundedLine.pin(.leading, to: .leading, of: titleLabel, withInset: -10)
        roundedLine.pin(.trailing, to: .trailing, of: titleLabel, withInset: 10)
        roundedLine.pin(.bottom, to: .bottom, of: titleLabel, withInset: 6)
        roundedLine.pin(.bottom, to: .bottom, of: self)
        leftLine.pin(.leading, to: .leading, of: self)
        leftLine.pin(.trailing, to: .leading, of: roundedLine)
        leftLine.center(.vertical, in: self)
        rightLine.pin(.leading, to: .trailing, of: roundedLine)
        rightLine.pin(.trailing, to: .trailing, of: self)
        rightLine.center(.vertical, in: self)
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        roundedLine.layer.cornerRadius = (roundedLine.bounds.height / 2)
    }
    
    // MARK: - Updating
    
    public func update(title: String?) {
        titleLabel.text = title
    }
}
