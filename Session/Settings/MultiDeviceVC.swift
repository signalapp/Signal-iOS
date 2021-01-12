
final class MultiDeviceVC : BaseVC {

    private let mnemonic: String = {
        let collection = OWSPrimaryStorageIdentityKeyStoreCollection
        let hexEncodedSeed: String! = OWSIdentityManager.shared().dbConnection.object(forKey: "LKLokiSeed", inCollection: collection) as! String?
        return Mnemonic.encode(hexEncodedString: hexEncodedSeed)
    }()

    // MARK: UI Components
    private lazy var toggleLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .systemFont(ofSize: Values.mediumFontSize)
        result.text = "Enable multi device"
        return result
    }()

    private lazy var toggle: UISwitch = {
        let result = UISwitch()
        result.onTintColor = Colors.accent
        return result
    }()

    private lazy var stepsRow: SettingRow = {
        let result = SettingRow(autoSize: true)
        result.isHidden = true
        return result
    }()

    private lazy var stepsLabel1: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.text = """
        1. Clear your other device if it currently has an account on it (Settings > Clear Data).

        2. On the landing page, click "Continue your Session".

        3. Enter the following words when prompted:
        """
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        return result
    }()

    private lazy var mnemonicLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = Fonts.spaceMono(ofSize: Values.smallFontSize)
        result.text = mnemonic
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.textAlignment = .center
        return result
    }()

    private lazy var copyButton: Button = {
        let result = Button(style: .prominentOutline, size: .medium)
        result.setTitle(NSLocalizedString("copy", comment: ""), for: UIControl.State.normal)
        result.addTarget(self, action: #selector(copyMnemonic), for: UIControl.Event.touchUpInside)
        return result
    }()

    private lazy var stepsLabel2: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.text = """
        4. Enter your display name.

        5. That's it!
        """
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        return result
    }()

    // MARK: Initialization
    override func viewDidLoad() {
        super.viewDidLoad()
        setUpUI()
    }

    private func setUpUI() {
        setUpGradientBackground()
        setUpNavBarStyle()
        setNavBarTitle("Multi Device (Beta)")
        // Back button
        let backButton = UIBarButtonItem(title: "Back", style: .plain, target: nil, action: nil)
        backButton.tintColor = Colors.text
        navigationItem.backBarButtonItem = backButton
        // Toggle
        toggle.addTarget(self, action: #selector(handleToggle), for: UIControl.Event.valueChanged)
        let toggleStackView = UIStackView(arrangedSubviews: [ toggleLabel, toggle ])
        toggleStackView.axis = .horizontal
        toggleStackView.spacing = Values.mediumSpacing
        toggleStackView.alignment = .center
        let toggleRow = SettingRow()
        toggleRow.contentView.addSubview(toggleStackView)
        toggleStackView.pin(to: toggleRow.contentView, withInset: Values.mediumSpacing)
        // Steps
        let mnemonicLabelContainer = UIView()
        mnemonicLabelContainer.addSubview(mnemonicLabel)
        mnemonicLabel.pin(to: mnemonicLabelContainer, withInset: isIPhone6OrSmaller ? 4 : Values.smallSpacing)
        mnemonicLabelContainer.layer.cornerRadius = Values.textFieldCornerRadius
        mnemonicLabelContainer.layer.borderWidth = Values.borderThickness
        mnemonicLabelContainer.layer.borderColor = Colors.text.cgColor
        let stepsLabel1Container = UIView()
        stepsLabel1Container.addSubview(stepsLabel1)
        stepsLabel1.pin(.leading, to: .leading, of: stepsLabel1Container, withInset: Values.smallSpacing)
        stepsLabel1Container.pin(.trailing, to: .trailing, of: stepsLabel1, withInset: Values.smallSpacing)
        stepsLabel1.pin([ UIView.VerticalEdge.top, UIView.VerticalEdge.bottom ], to: stepsLabel1Container)
        let stepsLabel2Container = UIView()
        stepsLabel2Container.addSubview(stepsLabel2)
        stepsLabel2.pin(.leading, to: .leading, of: stepsLabel2Container, withInset: Values.smallSpacing)
        stepsLabel2Container.pin(.trailing, to: .trailing, of: stepsLabel2, withInset: Values.smallSpacing)
        stepsLabel2.pin([ UIView.VerticalEdge.top, UIView.VerticalEdge.bottom ], to: stepsLabel2Container)
        let stepsStackView = UIStackView(arrangedSubviews: [ stepsLabel1Container, mnemonicLabelContainer, copyButton, stepsLabel2Container ])
        stepsStackView.axis = .vertical
        stepsStackView.spacing = Values.mediumSpacing
        stepsRow.contentView.addSubview(stepsStackView)
        stepsStackView.pin(to: stepsRow.contentView, withInset: Values.mediumSpacing)
        // Main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ toggleRow, stepsRow ])
        mainStackView.axis = .vertical
        mainStackView.spacing = Values.mediumSpacing
        mainStackView.isLayoutMarginsRelativeArrangement = true
        mainStackView.layoutMargins = UIEdgeInsets(uniform: Values.mediumSpacing)
        mainStackView.set(.width, to: UIScreen.main.bounds.width)
        // Scroll view
        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.addSubview(mainStackView)
        mainStackView.pin(to: scrollView)
        view.addSubview(scrollView)
        scrollView.pin(to: view)
    }

    // MARK: Updating
    @objc private func enableCopyButton() {
        copyButton.isUserInteractionEnabled = true
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle(NSLocalizedString("copy", comment: ""), for: UIControl.State.normal)
        }, completion: nil)
    }

    // MARK: Interaction
    @objc private func handleToggle() {
        stepsRow.isHidden = !toggle.isOn
    }

    @objc private func copyMnemonic() {
        UIPasteboard.general.string = mnemonic
        copyButton.isUserInteractionEnabled = false
        UIView.transition(with: copyButton, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.copyButton.setTitle("Copied", for: UIControl.State.normal)
        }, completion: nil)
        Timer.scheduledTimer(timeInterval: 4, target: self, selector: #selector(enableCopyButton), userInfo: nil, repeats: false)
    }
}
