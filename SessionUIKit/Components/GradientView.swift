// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

public class GradientView: UIView {
    var oldBounds: CGRect = .zero
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        guard oldBounds != bounds else { return }
        
        self.oldBounds = bounds
        
        self.layer.sublayers?
            .compactMap { $0 as? CAGradientLayer }
            .forEach { $0.frame = bounds }
    }
}
