// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

public extension UIViewController {
    func findFrontmostViewController(ignoringAlerts: Bool) -> UIViewController {
        var visitedViewControllers: [UIViewController] = []
        
        var viewController: UIViewController = self
        
        while true {
            visitedViewControllers.append(viewController)
            
            var nextViewController: UIViewController? = viewController.presentedViewController
            
            if let nextViewController: UIViewController = nextViewController {
                if !ignoringAlerts || !(nextViewController is UIAlertController) {
                    if visitedViewControllers.contains(nextViewController) {
                        // Cycle detected
                        return viewController
                    }
                    
                    viewController = nextViewController
                    continue
                }
            }
            
            if let navController: UINavigationController = viewController as? UINavigationController {
                nextViewController = navController.topViewController
                
                if let nextViewController: UIViewController = nextViewController {
                    if !ignoringAlerts || !(nextViewController is UIAlertController) {
                        if visitedViewControllers.contains(nextViewController) {
                            // Cycle detected
                            return viewController
                        }
                        
                        viewController = nextViewController
                        continue
                    }
                }
                
                break
            }
            
            break
        }
        
        return viewController
    }
    
    func createOWSBackButton() -> UIBarButtonItem {
        return UIViewController.createOWSBackButton(target: self, selector: #selector(backButtonPressed))
    }
    
    static func createOWSBackButton(target: Any?, selector: Selector) -> UIBarButtonItem {
        let backButton: UIButton = UIButton(type: .custom)
        
        let isRTL: Bool = CurrentAppContext().isRTL

        // Nudge closer to the left edge to match default back button item.
        let extraLeftPadding: CGFloat = (isRTL ? 0 : -8)

        // Give some extra hit area to the back button. This is a little smaller
        // than the default back button, but makes sense for our left aligned title
        // view in the MessagesViewController
        let extraRightPadding: CGFloat = (isRTL ? -0 : 10)

        // Extra hit area above/below
        let extraHeightPadding: CGFloat = 8

        // Matching the default backbutton placement is tricky.
        // We can't just adjust the imageEdgeInsets on a UIBarButtonItem directly,
        // so we adjust the imageEdgeInsets on a UIButton, then wrap that
        // in a UIBarButtonItem.
        backButton.addTarget(target, action: selector, for: .touchUpInside)
        
        let config: UIImage.Configuration = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        backButton.setImage(
            UIImage(systemName: "chevron.backward", withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate),
            for: .normal
        )
        backButton.themeTintColor = .textPrimary
        backButton.contentHorizontalAlignment = .left
        backButton.imageEdgeInsets = UIEdgeInsets(top: 0, leading: extraLeftPadding, bottom: 0, trailing: 0)
        backButton.frame = CGRect(
            x: 0,
            y: 0,
            width: ((backButton.image(for: .normal)?.size.width ?? 0) + extraRightPadding),
            height: ((backButton.image(for: .normal)?.size.height ?? 0) + extraHeightPadding)
        )

        let backItem: UIBarButtonItem = UIBarButtonItem(
            customView: backButton,
            accessibilityIdentifier: "\(type(of: self)).back"
        )
        backItem.width = backButton.frame.width

        return backItem;
    }
    
    // MARK: - Event Handling

    @objc func backButtonPressed() {
        self.navigationController?.popViewController(animated: true)
    }
}
