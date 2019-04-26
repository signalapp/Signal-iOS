import UIKit
import PromiseKit

final class OnboardingPublicKeyViewController : OnboardingBaseViewController {
    private var keyPair: ECKeyPair! { didSet { updateMnemonic() } }
    private var hexEncodedPublicKey: String!
    private var mnemonic: String! { didSet { mnemonicLabel.text = mnemonic } }
    
    private lazy var mnemonicLabel: UILabel = {
        let result = createExplanationLabel(text: "")
        result.accessibilityIdentifier = "onboarding.publicKeyStep.mnemonicLabel"
        result.alpha = 0.8
        var fontTraits = result.font.fontDescriptor.symbolicTraits
        fontTraits.insert(.traitItalic)
        result.font = UIFont(descriptor: result.font.fontDescriptor.withSymbolicTraits(fontTraits)!, size: result.font.pointSize)
        return result
    }()
    
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
        let explanationLabel = createExplanationLabel(text: NSLocalizedString("Please save the seed below in a safe location. They can be used to restore your account if you lose access or migrate to a new device.", comment: ""))
        explanationLabel.accessibilityIdentifier = "onboarding.publicKeyStep.explanationLabel"
        let bottomSpacer = UIView.vStretchingSpacer()
        let registerButton = button(title: NSLocalizedString("Register", comment: ""), selector: #selector(register))
        registerButton.accessibilityIdentifier = "onboarding.publicKeyStep.registerButton"
        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            topSpacer,
            explanationLabel,
            UIView.spacer(withHeight: 32),
            mnemonicLabel,
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
    
    @objc private func register() {
        let accountManager = TSAccountManager.sharedInstance()
        accountManager.phoneNumberAwaitingVerification = hexEncodedPublicKey
        accountManager.didRegister()
        onboardingController.verificationDidComplete(fromView: self)
    }
}
