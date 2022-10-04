// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

public class BaseVC: UIViewController {
    public override var preferredStatusBarStyle: UIStatusBarStyle {
        return ThemeManager.currentTheme.statusBarStyle
    }

    lazy var navBarTitleLabel: UILabel = {
        let result = UILabel()
        result.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        result.themeTextColor = .textPrimary
        result.textAlignment = .center
        result.alpha = 1
        
        return result
    }()

    lazy var crossfadeLabel: UILabel = {
        let result = UILabel()
        result.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        result.themeTextColor = .textPrimary
        result.textAlignment = .center
        result.alpha = 0
        
        return result
    }()

    public override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.backButtonTitle = ""
        view.themeBackgroundColor = .backgroundPrimary
        ThemeManager.applyNavigationStylingIfNeeded(to: self)
        
        setNeedsStatusBarAppearanceUpdate()
    }

    internal func setNavBarTitle(_ title: String, customFontSize: CGFloat? = nil) {
        let container = UIView()
        navBarTitleLabel.text = title
        crossfadeLabel.text = title
        
        if let customFontSize = customFontSize {
            navBarTitleLabel.font = .boldSystemFont(ofSize: customFontSize)
            crossfadeLabel.font = .boldSystemFont(ofSize: customFontSize)
        }
        
        container.addSubview(navBarTitleLabel)
        container.addSubview(crossfadeLabel)
        
        navBarTitleLabel.pin(to: container)
        crossfadeLabel.pin(to: container)
        
        navigationItem.titleView = container
    }
    
    internal func setUpNavBarSessionHeading() {
        let headingImageView = UIImageView(
            image: UIImage(named: "SessionHeading")?
                .withRenderingMode(.alwaysTemplate)
        )
        headingImageView.themeTintColor = .textPrimary
        headingImageView.contentMode = .scaleAspectFit
        headingImageView.set(.width, to: 150)
        headingImageView.set(.height, to: Values.mediumFontSize)
        
        navigationItem.titleView = headingImageView
    }

    internal func setUpNavBarSessionIcon() {
        let logoImageView = UIImageView()
        logoImageView.image = #imageLiteral(resourceName: "SessionGreen32")
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.set(.width, to: 32)
        logoImageView.set(.height, to: 32)
        
        navigationItem.titleView = logoImageView
    }
}
