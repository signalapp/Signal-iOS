//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

public extension NSObject {

    public func navigationBarButton(imageName: String,
                                     selector: Selector) -> UIView {
        let button = OWSButton()
        button.setImage(imageName: imageName)
        button.tintColor = .white
        button.addTarget(self, action: selector, for: .touchUpInside)
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowRadius = 2
        button.layer.shadowOpacity = 0.66
        return button
    }
}

// MARK: -

public extension UIViewController {

    public func updateNavigationBar(navigationBarItems: [UIView]) {
        guard navigationBarItems.count > 0 else {
            self.navigationItem.rightBarButtonItems = []
            return
        }

        let stackView = UIStackView(arrangedSubviews: navigationBarItems)
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center

        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: stackView)
    }
}
