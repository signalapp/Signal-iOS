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
        button.layer.shadowOffset = .zero
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
        
        // Loki: Set navigation bar background color
        let navigationBar = navigationController!.navigationBar
        navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
        navigationBar.shadowImage = UIImage()
        navigationBar.isTranslucent = false
        navigationBar.barTintColor = UIColor(rgbHex: 0x161616) // Colors.navigationBarBackground
        navigationBar.backgroundColor = UIColor(rgbHex: 0x161616) // Colors.navigationBarBackground
        let backgroundImage = UIImage(color: UIColor(rgbHex: 0x161616)) // Colors.navigationBarBackground
        navigationBar.setBackgroundImage(backgroundImage, for: .default)
    }
}
