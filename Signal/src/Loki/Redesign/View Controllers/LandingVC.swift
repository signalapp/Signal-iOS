
final class LandingVC : UIViewController {
    
    // MARK: Settings
    override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent }
    
    // MARK: Lifecycle
    override func viewDidLoad() {
        // Set gradient background
        view.backgroundColor = .clear
        let gradient = Gradients.defaultLokiBackground
        view.setGradient(gradient)
        // Set up navigation bar
        let navigationBar = navigationController!.navigationBar
        navigationBar.setBackgroundImage(UIImage(), for: UIBarMetrics.default)
        navigationBar.shadowImage = UIImage()
        navigationBar.isTranslucent = false
        navigationBar.barTintColor = Colors.navigationBarBackground
        // Set up logo image view
        let logoImageView = UIImageView()
        logoImageView.image = #imageLiteral(resourceName: "Loki")
        logoImageView.contentMode = .scaleAspectFit
        logoImageView.set(.width, to: 32)
        logoImageView.set(.height, to: 32)
        navigationItem.titleView = logoImageView
        // Set up title label
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: Values.veryLargeFontSize)
        titleLabel.text = NSLocalizedString("Your Loki Messenger begins here...", comment: "")
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        // Set up title label container
        let titleLabelContainer = UIView()
        titleLabelContainer.addSubview(titleLabel)
        titleLabel.pin(.leading, to: .leading, of: titleLabelContainer, withInset: Values.veryLargeSpacing)
        titleLabel.pin(.top, to: .top, of: titleLabelContainer)
        titleLabelContainer.pin(.trailing, to: .trailing, of: titleLabel, withInset: Values.veryLargeSpacing)
        titleLabelContainer.pin(.bottom, to: .bottom, of: titleLabel)
        // Set up fake chat view
        let fakeChatView = FakeChatView()
        // Set up main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ titleLabelContainer, fakeChatView ])
        mainStackView.axis = .vertical
        mainStackView.spacing = Values.mediumSpacing // The fake chat view has an internal top margin
        mainStackView.alignment = .fill
        view.addSubview(mainStackView)
        mainStackView.pin(.leading, to: .leading, of: view)
        view.pin(.trailing, to: .trailing, of: mainStackView)
        mainStackView.set(.height, to: Values.fakeChatViewHeight)
        mainStackView.center(.vertical, in: view)
        // Set up view
        let screen = UIScreen.main.bounds
        view.set(.width, to: screen.width)
        view.set(.height, to: screen.height)
        // Set up register button
        let registerButton = Button(style: .prominentFilled, size: .large)
        registerButton.setTitle(NSLocalizedString("Create Account", comment: ""), for: UIControl.State.normal)
        registerButton.titleLabel!.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        // Set up restore button
        let restoreButton = Button(style: .prominentOutline, size: .large)
        restoreButton.setTitle(NSLocalizedString("Continue your Loki Messenger", comment: ""), for: UIControl.State.normal)
        restoreButton.titleLabel!.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        // Set up button stack view
        let buttonStackView = UIStackView(arrangedSubviews: [ registerButton, restoreButton ])
        buttonStackView.axis = .vertical
        buttonStackView.spacing = Values.mediumSpacing
        buttonStackView.alignment = .fill
        view.addSubview(buttonStackView)
        buttonStackView.pin(.leading, to: .leading, of: view, withInset: Values.massiveSpacing)
        view.pin(.trailing, to: .trailing, of: buttonStackView, withInset: Values.massiveSpacing)
        view.pin(.bottom, to: .bottom, of: buttonStackView, withInset: Values.restoreButtonBottomOffset)
    }
}
