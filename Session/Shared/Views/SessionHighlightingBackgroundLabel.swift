// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionUtilitiesKit

public class SessionHighlightingBackgroundLabel: UIView {
    var text: String? {
        get { label.text }
        set { label.text = newValue }
    }
    
    var themeTextColor: ThemeValue? {
        get { label.themeTextColor }
        set { label.themeTextColor = newValue }
    }
    
    // MARK: - Components
    
    private let label: UILabel = {
        let result: UILabel = UILabel()
        result.translatesAutoresizingMaskIntoConstraints = false
        result.font = .boldSystemFont(ofSize: Values.smallFontSize)
        result.themeTextColor = .textPrimary
        result.setContentHuggingHigh()
        result.setCompressionResistanceHigh()
        
        return result
    }()
    
    // MARK: - Initialization
    
    init() {
        super.init(frame: .zero)
        
        self.themeBackgroundColor = .solidButton_background
        self.layer.cornerRadius = 5
        
        self.setupViewHierarchy()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Layout
    
    private func setupViewHierarchy() {
        addSubview(label)
        
        label.pin(to: self, withInset: Values.smallSpacing)
    }
    
    // MARK: - Interaction
    
    func setHighlighted(_ highlighted: Bool, animated: Bool) {
        self.themeBackgroundColor = (highlighted ?
            .highlighted(.solidButton_background) :
            .solidButton_background
        )
    }
    
    func setSelected(_ selected: Bool, animated: Bool) {
        // Note: When initially triggering a selection we will be coming from the highlighted
        // state but will have already set highlighted to false at this stage, as a result we
        // need to swap back into the "highlighted" state so we can properly unhighlight within
        // the "deselect" animation
        guard !selected else {
            self.themeBackgroundColor = .highlighted(.solidButton_background)
            return
        }
        guard animated else {
            self.themeBackgroundColor = .solidButton_background
            return
        }
        
        UIView.animate(withDuration: 0.4) { [weak self] in
            self?.themeBackgroundColor = .solidButton_background
        }
    }
}
