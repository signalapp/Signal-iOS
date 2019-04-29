import UIKit
import PromiseKit

final class OnboardingPublicKeyViewController : OnboardingBaseViewController {
    private var keyPair: ECKeyPair! { didSet { updateMnemonic() } }
    private var hexEncodedPublicKey: String!
    private var mnemonic: String! { didSet { mnemonicLabel.text = mnemonic } }
    private var userName: String?
    
    private lazy var mnemonicLabel: UILabel = {
        let result = createExplanationLabel(text: "")
        result.accessibilityIdentifier = "onboarding.publicKeyStep.mnemonicLabel"
        result.alpha = 0.8
        var fontTraits = result.font.fontDescriptor.symbolicTraits
        fontTraits.insert(.traitItalic)
        result.font = UIFont(descriptor: result.font.fontDescriptor.withSymbolicTraits(fontTraits)!, size: result.font.pointSize)
        return result
    }()

    private lazy var copyButton: OWSFlatButton = {
        let result = createLinkButton(title: NSLocalizedString("Copy", comment: ""), selector: #selector(copyMnemonic))
        result.accessibilityIdentifier = "onboarding.publicKeyStep.copyButton"
        return result
    }()
    
    init(onboardingController: OnboardingController, userName: String?) {
        super.init(onboardingController: onboardingController)
        self.userName = userName
    }
    
    override public func viewDidLoad() {
        super.loadView()
        setUpViewHierarchy()
        updateKeyPair()
    }
    
    private func setUpViewHierarchy() {
        view.backgroundColor = Theme.backgroundColor
        view.layoutMargins = .zero
        let titleLabel = createTitleLabel(text: NSLocalizedString("Create Your Loki Messenger Account", comment: ""))
        titleLabel.accessibilityIdentifier = "onboarding.publicKeyStep.titleLabel"
        let topSpacer = UIView.vStretchingSpacer()
        let explanationLabel = createExplanationLabel(text: NSLocalizedString("Please save the seed below in a safe location. It can be used to restore your account if you lose access, or to migrate to a new device.", comment: ""))
        explanationLabel.accessibilityIdentifier = "onboarding.publicKeyStep.explanationLabel"
        let copyButton = createLinkButton(title: NSLocalizedString("Copy", comment: ""), selector: #selector(copyMnemonic))
        copyButton.accessibilityIdentifier = "onboarding.publicKeyStep.copyButton"
        let bottomSpacer = UIView.vStretchingSpacer()
        let registerButton = createButton(title: NSLocalizedString("Register", comment: ""), selector: #selector(register))
        registerButton.accessibilityIdentifier = "onboarding.publicKeyStep.registerButton"
        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            topSpacer,
            explanationLabel,
            UIView.spacer(withHeight: 32),
            mnemonicLabel,
            UIView.spacer(withHeight: 24),
            copyButton,
            bottomSpacer,
            registerButton
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.layoutMargins = UIEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)
        stackView.isLayoutMarginsRelativeArrangement = true
        view.addSubview(stackView)
        stackView.autoPinWidthToSuperview()
        stackView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        autoPinView(toBottomOfViewControllerOrKeyboard: stackView, avoidNotch: true)
        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)
    }
    
    private func updateKeyPair() {
        let identityManager = OWSIdentityManager.shared()
        identityManager.generateNewIdentityKey() // Generates and stores a new key pair
        keyPair = identityManager.identityKeyPair()!
    }
    
    private func updateMnemonic() {
        hexEncodedPublicKey = keyPair.publicKey.map { String(format: "%02hhx", $0) }.joined()
        mnemonic = Mnemonic.encode(hexEncodedString: hexEncodedPublicKey)
    }

    @objc private func copyMnemonic() {
        UIPasteboard.general.string = mnemonic
        copyButton.isUserInteractionEnabled = false
        copyButton.setTitle(title: NSLocalizedString("Copied ✓", comment: ""), font: .ows_dynamicTypeBodyClamped, titleColor: .ows_materialBlue)
        Timer.scheduledTimer(timeInterval: 4, target: self, selector: #selector(enableCopyButton), userInfo: nil, repeats: false)
    }

    @objc private func enableCopyButton() {
        copyButton.isUserInteractionEnabled = true
        copyButton.setTitle(title: NSLocalizedString("Copy", comment: ""), font: .ows_dynamicTypeBodyClamped, titleColor: .ows_materialBlue)
    }

    @objc private func register() {
        let accountManager = TSAccountManager.sharedInstance()
        accountManager.phoneNumberAwaitingVerification = hexEncodedPublicKey
        accountManager.didRegister()
        
        let verificationComplete: () -> Void = { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.onboardingController.verificationDidComplete(fromView: strongSelf)
        }
        
        if let userName = userName {
            // Try save the profile name
            OWSProfileManager.shared().updateLocalProfileName(userName, avatarImage: nil, success: verificationComplete, failure: {
                Logger.warn("Failed to set user name")
                verificationComplete()
            })
        } else {
            verificationComplete()
        }

    }
}
