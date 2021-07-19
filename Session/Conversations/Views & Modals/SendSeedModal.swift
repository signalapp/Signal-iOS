
final class SendSeedModal : Modal {
    var proceed: (() -> Void)? = nil
    
    private lazy var titleLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .boldSystemFont(ofSize: Values.largeFontSize)
        result.text = NSLocalizedString("modal_send_seed_title", comment: "")
        result.textAlignment = .center
        return result
    }()
    
    private lazy var explanationLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.text = NSLocalizedString("modal_send_seed_explanation", comment: "")
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.textAlignment = .center
        return result
    }()
    
    private lazy var sendSeedButton: UIButton = {
        let result = UIButton()
        result.set(.height, to: Values.mediumButtonHeight)
        result.layer.cornerRadius = Modal.buttonCornerRadius
        if isDarkMode {
            result.backgroundColor = Colors.destructive
        }
        result.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        result.setTitleColor(isLightMode ? Colors.destructive : Colors.text, for: UIControl.State.normal)
        result.setTitle(NSLocalizedString("modal_send_seed_send_button_title", comment: ""), for: UIControl.State.normal)
        result.addTarget(self, action: #selector(sendSeed), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var buttonStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ cancelButton, sendSeedButton ])
        result.axis = .horizontal
        result.spacing = Values.mediumSpacing
        result.distribution = .fillEqually
        return result
    }()
    
    private lazy var mainStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ titleLabel, explanationLabel, buttonStackView ])
        result.axis = .vertical
        result.spacing = Values.largeSpacing
        return result
    }()
    
    override func populateContentView() {
        contentView.addSubview(mainStackView)
        mainStackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        mainStackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: mainStackView, withInset: Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: mainStackView, withInset: Values.largeSpacing)
    }
    
    // MARK: Interaction
    @objc private func sendSeed() {
        proceed?()
        presentingViewController?.dismiss(animated: true, completion: nil)
    }
}
