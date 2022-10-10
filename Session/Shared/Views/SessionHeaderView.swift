// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

class SessionHeaderView: UITableViewHeaderFooterView {
    private lazy var emptyHeightConstraint: NSLayoutConstraint = self.heightAnchor
        .constraint(equalToConstant: (Values.verySmallSpacing * 2))
    private lazy var filledHeightConstraint: NSLayoutConstraint = self.heightAnchor
        .constraint(greaterThanOrEqualToConstant: Values.mediumSpacing)
    
    // MARK: - UI
    
    private let stackView: UIStackView = {
        let result: UIStackView = UIStackView()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.axis = .vertical
        result.distribution = .fill
        result.alignment = .fill
        result.isLayoutMarginsRelativeArrangement = true
        
        return result
    }()
    
    private let titleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.font = .systemFont(ofSize: Values.mediumFontSize)
        result.themeTextColor = .textSecondary
        
        return result
    }()
    
    private let separator: UIView = UIView.separator()
    
    // MARK: - Initialization
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        
        self.backgroundView = UIView()
        self.backgroundView?.themeBackgroundColor = .backgroundPrimary
        
        addSubview(stackView)
        addSubview(separator)
        
        stackView.addArrangedSubview(titleLabel)
        
        setupLayout()
    }
    
    required init?(coder: NSCoder) {
        fatalError("use init(reuseIdentifier:) instead")
    }
    
    private func setupLayout() {
        stackView.pin(to: self)
        
        separator.pin(.left, to: .left, of: self)
        separator.pin(.right, to: .right, of: self)
        separator.pin(.bottom, to: .bottom, of: self)
    }
    
    // MARK: - Content
    
    public func update(
        style: SessionCell.Style = .rounded,
        title: String?,
        hasSeparator: Bool
    ) {
        let titleIsEmpty: Bool = (title ?? "").isEmpty
        let edgePadding: CGFloat = {
            switch style {
                case .rounded:
                    // Align to the start of the text in the cell
                    return (Values.largeSpacing + Values.mediumSpacing)
                
                case .edgeToEdge, .roundedEdgeToEdge: return Values.largeSpacing
            }
        }()
        
        titleLabel.text = title
        titleLabel.isHidden = titleIsEmpty
        stackView.layoutMargins = UIEdgeInsets(
            top: (titleIsEmpty ? Values.verySmallSpacing : Values.mediumSpacing),
            left: edgePadding,
            bottom: (titleIsEmpty ? Values.verySmallSpacing : Values.mediumSpacing),
            right: edgePadding
        )
        emptyHeightConstraint.isActive = titleIsEmpty
        filledHeightConstraint.isActive = !titleIsEmpty
        separator.isHidden = (style == .rounded || !hasSeparator)
        
        self.layoutIfNeeded()
    }
}
