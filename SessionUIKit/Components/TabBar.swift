// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

public final class TabBar: UIView {
    private let tabs: [Tab]
    private var accentLineViewHorizontalCenteringConstraint: NSLayoutConstraint!
    private var accentLineViewWidthConstraint: NSLayoutConstraint!
    
    // MARK: - Components
    
    private lazy var tabLabels: [UILabel] = tabs.map { tab in
        let result = UILabel()
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.text = tab.title
        result.themeTextColor = .textPrimary
        result.textAlignment = .center
        result.alpha = Values.mediumOpacity
        result.set(.height, to: TabBar.snHeight - Values.separatorThickness - Values.accentLineThickness)
        
        return result
    }
    
    private lazy var accentLineView: UIView = {
        let result = UIView()
        result.themeBackgroundColor = .primary
        return result
    }()
    
    // MARK: - Types
    
    public struct Tab {
        let title: String
        let onTap: () -> Void

        public init(title: String, onTap: @escaping () -> Void) {
            self.title = title
            self.onTap = onTap
        }
    }
    
    // MARK: - Settings
    
    public static let snHeight = isIPhone5OrSmaller ? CGFloat(32) : CGFloat(48)
    
    // MARK: - Lifecycle
    
    public init(tabs: [Tab]) {
        self.tabs = tabs
        super.init(frame: CGRect.zero)
        setUpViewHierarchy()
    }
    
    public override init(frame: CGRect) {
        preconditionFailure("Use init(tabs:) instead.")
    }
    
    public required init?(coder: NSCoder) {
        preconditionFailure("Use init(tabs:) instead.")
    }
    
    private func setUpViewHierarchy() {
        set(.height, to: TabBar.snHeight)
        
        tabLabels.forEach { tabLabel in
            let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTabLabelTapped(_:)))
            tabLabel.addGestureRecognizer(tapGestureRecognizer)
        }
        
        let tabLabelStackView = UIStackView(arrangedSubviews: tabLabels)
        tabLabelStackView.axis = .horizontal
        tabLabelStackView.distribution = .fillEqually
        tabLabelStackView.spacing = Values.mediumSpacing
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTabLabelTapped(_:)))
        tabLabelStackView.addGestureRecognizer(tapGestureRecognizer)
        tabLabelStackView.set(.height, to: TabBar.snHeight - Values.separatorThickness - Values.accentLineThickness)
        addSubview(tabLabelStackView)
        
        let separator = UIView()
        separator.themeBackgroundColor = .borderSeparator
        separator.set(.height, to: Values.separatorThickness)
        addSubview(separator)
        
        accentLineView.set(.height, to: Values.accentLineThickness)
        addSubview(accentLineView)
        
        tabLabelStackView.pin(.leading, to: .leading, of: self)
        tabLabelStackView.pin(.top, to: .top, of: self)
        
        pin(.trailing, to: .trailing, of: tabLabelStackView)
        separator.pin(.leading, to: .leading, of: self)
        separator.pin(.top, to: .bottom, of: tabLabelStackView)
        
        pin(.trailing, to: .trailing, of: separator)
        accentLineView.translatesAutoresizingMaskIntoConstraints = false
        
        selectTab(at: 0, withAnimatedTransition: false)
        
        accentLineView.pin(.top, to: .bottom, of: separator)
        pin(.bottom, to: .bottom, of: accentLineView)
    }

    // MARK: - Updating
    
    public func selectTab(at index: Int, withAnimatedTransition isAnimated: Bool = true) {
        let tabLabel = tabLabels[index]
        accentLineViewHorizontalCenteringConstraint?.isActive = false
        accentLineViewHorizontalCenteringConstraint = accentLineView.centerXAnchor.constraint(equalTo: tabLabel.centerXAnchor)
        accentLineViewHorizontalCenteringConstraint.isActive = true
        accentLineViewWidthConstraint?.isActive = false
        accentLineViewWidthConstraint = accentLineView.widthAnchor.constraint(equalTo: tabLabel.widthAnchor)
        accentLineViewWidthConstraint.isActive = true
        
        var tabLabelsCopy = tabLabels
        tabLabelsCopy.remove(at: index)
        
        UIView.animate(withDuration: isAnimated ? 0.25 : 0) {
            tabLabel.alpha = 1
            tabLabelsCopy.forEach { $0.alpha = Values.mediumOpacity }
            
            self.layoutIfNeeded()
        }
    }
    
    // MARK: - Interaction
    
    @objc private func handleTabLabelTapped(_ sender: UITapGestureRecognizer) {
        guard let tabLabel = tabLabels.first(where: { $0.bounds.contains(sender.location(in: $0)) }), let index = tabLabels.firstIndex(of: tabLabel) else { return }
        selectTab(at: index)
        let tab = tabs[index]
        tab.onTap()
    }
}
