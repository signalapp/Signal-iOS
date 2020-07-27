
class BaseVC : UIViewController {

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
        NotificationCenter.default.addObserver(self, selector: #selector(handleUnexpectedDeviceLinkRequestReceivedNotification), name: .unexpectedDeviceLinkRequestReceived, object: nil)
    }

    internal func setUpGradientBackground() {
        view.backgroundColor = .clear
        let gradient = Gradients.defaultLokiBackground
        view.setGradient(gradient)
    }

    internal func setUpNavBarStyle() {
        let navigationBar = navigationController!.navigationBar
        navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
        navigationBar.shadowImage = UIImage()
        navigationBar.isTranslucent = false
        navigationBar.barTintColor = Colors.navigationBarBackground
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

    @objc private func handleUnexpectedDeviceLinkRequestReceivedNotification() {
        guard DeviceLinkingUtilities.shouldShowUnexpectedDeviceLinkRequestReceivedAlert else { return }
        DispatchQueue.main.async {
            let alert = UIAlertController(title: "Device Link Request Received", message: "Open the device link screen by going to \"Settings\" > \"Devices\" > \"Link a Device\" to link your devices.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }
}
