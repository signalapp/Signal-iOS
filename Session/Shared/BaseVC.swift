// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

class BaseVC: UIViewController {
    override var preferredStatusBarStyle: UIStatusBarStyle { return ThemeManager.currentTheme.statusBarStyle }

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

    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.backButtonTitle = ""
        view.themeBackgroundColor = .backgroundPrimary
        
        setNeedsStatusBarAppearanceUpdate()
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppModeChangedNotification(_:)), name: .appModeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive(_:)), name: .OWSApplicationDidBecomeActive, object: nil)
    }
    
    internal func ensureWindowBackground() {
        let appMode = AppModeManager.shared.currentAppMode
        switch appMode {
        case .light:
            UIApplication.shared.delegate?.window??.backgroundColor = .white
        case .dark:
            UIApplication.shared.delegate?.window??.backgroundColor = .black
        }
    }

    internal func setUpGradientBackground() {
        hasGradient = true
        view.backgroundColor = .clear
        let gradient = Gradients.defaultBackground
        view.setGradient(gradient)
    }

    internal func setUpNavBarStyle() {
        guard let navigationBar = navigationController?.navigationBar else { return }
        
        if #available(iOS 15.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = Colors.navigationBarBackground
            appearance.shadowColor = .clear
            navigationBar.standardAppearance = appearance;
            navigationBar.scrollEdgeAppearance = navigationBar.standardAppearance
        } else {
            navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
            navigationBar.shadowImage = UIImage()
            navigationBar.isTranslucent = false
            navigationBar.barTintColor = Colors.navigationBarBackground
        }
        
        navigationItem.backButtonTitle = ""
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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc func appDidBecomeActive(_ notification: Notification) {
        // To be implemented by child class
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        SNLog("Current trait collection: \(UITraitCollection.current), previous trait collection: \(previousTraitCollection)")
        
        if LKAppModeUtilities.isSystemDefault {
             NotificationCenter.default.post(name: .appModeChanged, object: nil)
        }
    }

    @objc internal func handleAppModeChangedNotification(_ notification: Notification) {
        if hasGradient {
            setUpGradientBackground() // Re-do the gradient
        }
        ensureWindowBackground()
    }
}
