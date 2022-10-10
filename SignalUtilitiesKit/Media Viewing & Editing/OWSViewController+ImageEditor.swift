//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit
import SessionUIKit

public extension NSObject {
    func navigationBarButton(imageName: String, selector: Selector) -> UIView {
        let button = OWSButton()
        button.setImage(imageName: imageName)
        button.themeTintColor = .textPrimary
        button.addTarget(self, action: selector, for: .touchUpInside)
        
        return button
    }
}

// MARK: -

public extension UIViewController {

    func updateNavigationBar(navigationBarItems: [UIView]) {
        guard navigationBarItems.count > 0 else {
            self.navigationItem.rightBarButtonItems = []
            return
        }

        let spacing: CGFloat = 16
        let stackView = UIStackView(arrangedSubviews: navigationBarItems)
        stackView.axis = .horizontal
        stackView.spacing = spacing
        stackView.alignment = .center
        
        // Ensure layout works on older versions of iOS.
        var stackSize = CGSize.zero
        for item in navigationBarItems {
            let itemSize = item.sizeThatFits(.zero)
            stackSize.width += itemSize.width + spacing
            stackSize.height = max(stackSize.height, itemSize.height)
        }
        if navigationBarItems.count > 0 {
            stackSize.width -= spacing
        }
        stackView.frame = CGRect(origin: .zero, size: stackSize)

        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: stackView)
    }
}
