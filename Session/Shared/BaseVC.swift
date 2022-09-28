
class BaseVC : UIViewController {
    private var hasGradient = false

    override var preferredStatusBarStyle: UIStatusBarStyle { return isLightMode ? .default : .lightContent }

    lazy var navBarTitleLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        result.alpha = 1
        result.textAlignment = .center
        return result
    }()

    lazy var crossfadeLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        result.alpha = 0
        result.textAlignment = .center
        return result
    }()

    override func viewDidLoad() {
        setNeedsStatusBarAppearanceUpdate()
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppModeChangedNotification(_:)), name: .appModeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive(_:)), name: .OWSApplicationDidBecomeActive, object: nil)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        if hasGradient {
            let frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            setUpGradientBackground(frame: frame)
        }
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

    internal func setUpGradientBackground(frame: CGRect = UIScreen.main.bounds) {
        hasGradient = true
        view.backgroundColor = .clear
        let gradient = Gradients.defaultBackground
        view.setGradient(gradient, frame: frame)
    }

    internal func setUpNavBarStyle() {
        guard let navigationBar = navigationController?.navigationBar else { return }
        
        if #available(iOS 15.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = hasGradient ? Colors.navigationBarBackground : view.backgroundColor
            appearance.shadowColor = .clear
            navigationBar.standardAppearance = appearance;
            navigationBar.scrollEdgeAppearance = navigationBar.standardAppearance
        } else {
            navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
            navigationBar.shadowImage = UIImage()
            navigationBar.isTranslucent = false
            navigationBar.barTintColor = hasGradient ? Colors.navigationBarBackground : view.backgroundColor
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
        navBarTitleLabel.pin(to: container)
        container.addSubview(crossfadeLabel)
        crossfadeLabel.pin(to: container)
        navigationItem.titleView = container
    }
    
    internal func setUpNavBarSessionHeading() {
        let headingImageView = UIImageView()
        headingImageView.tintColor = Colors.text
        headingImageView.image = UIImage(named: "SessionHeading")?.withRenderingMode(.alwaysTemplate)
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
        } else {
            view.backgroundColor = isLightMode ? UIColor(hex: 0xF9F9F9) : UIColor(hex: 0x1B1B1B)
        }
        ensureWindowBackground()
    }
}
