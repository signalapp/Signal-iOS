import UIKit
import SessionUIKit
import SessionSnodeKit
import SessionMessagingKit

@objc(LKNukeDataModal)
final class NukeDataModal : Modal {
    
    // MARK: Components
    private lazy var titleLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.text = NSLocalizedString("modal_clear_all_data_title", comment: "")
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.textAlignment = .center
        return result
    }()
    
    private lazy var explanationLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text.withAlphaComponent(Values.mediumOpacity)
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.text = NSLocalizedString("modal_clear_all_data_explanation", comment: "")
        result.numberOfLines = 0
        result.textAlignment = .center
        result.lineBreakMode = .byWordWrapping
        return result
    }()
    
    private lazy var clearDataButton: UIButton = {
        let result = UIButton()
        result.set(.height, to: Values.mediumButtonHeight)
        result.layer.cornerRadius = Modal.buttonCornerRadius
        if isDarkMode {
            result.backgroundColor = Colors.destructive
        }
        result.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        result.setTitleColor(isLightMode ? Colors.destructive : Colors.text, for: UIControl.State.normal)
        result.setTitle(NSLocalizedString("TXT_DELETE_TITLE", comment: ""), for: UIControl.State.normal)
        result.addTarget(self, action: #selector(clearAllData), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var buttonStackView1: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ cancelButton, clearDataButton ])
        result.axis = .horizontal
        result.spacing = Values.mediumSpacing
        result.distribution = .fillEqually
        return result
    }()
    
    private lazy var deviceOnlyButton: UIButton = {
        let result = UIButton()
        result.set(.height, to: Values.mediumButtonHeight)
        result.layer.cornerRadius = Modal.buttonCornerRadius
        result.backgroundColor = Colors.buttonBackground
        result.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        result.setTitleColor(Colors.text, for: UIControl.State.normal)
        result.setTitle(NSLocalizedString("modal_clear_all_data_device_only_button_title", comment: ""), for: UIControl.State.normal)
        result.addTarget(self, action: #selector(clearDeviceOnly), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var entireAccountButton: UIButton = {
        let result = UIButton()
        result.set(.height, to: Values.mediumButtonHeight)
        result.layer.cornerRadius = Modal.buttonCornerRadius
        if isDarkMode {
            result.backgroundColor = Colors.destructive
        }
        result.titleLabel!.font = .systemFont(ofSize: Values.smallFontSize)
        result.setTitleColor(isLightMode ? Colors.destructive : Colors.text, for: UIControl.State.normal)
        result.setTitle(NSLocalizedString("modal_clear_all_data_entire_account_button_title", comment: ""), for: UIControl.State.normal)
        result.addTarget(self, action: #selector(clearEntireAccount), for: UIControl.Event.touchUpInside)
        return result
    }()
    
    private lazy var buttonStackView2: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ deviceOnlyButton, entireAccountButton ])
        result.axis = .horizontal
        result.spacing = Values.mediumSpacing
        result.distribution = .fillEqually
        result.alpha = 0
        return result
    }()
    
    private lazy var buttonStackViewContainer: UIView = {
        let result = UIView()
        result.addSubview(buttonStackView2)
        buttonStackView2.pin(to: result)
        result.addSubview(buttonStackView1)
        buttonStackView1.pin(to: result)
        return result
    }()
    
    private lazy var mainStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ titleLabel, explanationLabel, buttonStackViewContainer ])
        result.axis = .vertical
        result.spacing = Values.largeSpacing
        return result
    }()
    
    // MARK: Lifecycle
    override func populateContentView() {
        contentView.addSubview(mainStackView)
        mainStackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        mainStackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: mainStackView, withInset: Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: mainStackView, withInset: Values.largeSpacing)
    }
    
    // MARK: Interaction
    @objc private func clearAllData() {
        UIView.animate(withDuration: 0.25) {
            self.buttonStackView1.alpha = 0
            self.buttonStackView2.alpha = 1
        }
        UIView.transition(with: explanationLabel, duration: 0.25, options: .transitionCrossDissolve, animations: {
            self.explanationLabel.text = NSLocalizedString("modal_clear_all_data_explanation_2", comment: "")
        }, completion: nil)
    }
    
    @objc private func clearDeviceOnly() {
        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { [weak self] _ in
            MessageSender.syncConfiguration(forceSyncNow: true).ensure(on: DispatchQueue.main) {
                self?.dismiss(animated: true, completion: nil) // Dismiss the loader
                UserDefaults.removeAll() // Not done in the nuke data implementation as unlinking requires this to happen later
                General.Cache.cachedEncodedPublicKey.mutate { $0 = nil } // Remove the cached key so it gets re-cached on next access
                NotificationCenter.default.post(name: .dataNukeRequested, object: nil)
            }.retainUntilComplete()
        }
    }
    
    @objc private func clearEntireAccount() {
        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { [weak self] _ in
            SnodeAPI.clearAllData().done(on: DispatchQueue.main) { confirmations in
                self?.dismiss(animated: true, completion: nil) // Dismiss the loader
                let potentiallyMaliciousSnodes = confirmations.compactMap { $0.value == false ? $0.key : nil }
                if potentiallyMaliciousSnodes.isEmpty {
                    General.Cache.cachedEncodedPublicKey.mutate { $0 = nil } // Remove the cached key so it gets re-cached on next access
                    UserDefaults.removeAll() // Not done in the nuke data implementation as unlinking requires this to happen later
                    NotificationCenter.default.post(name: .dataNukeRequested, object: nil)
                } else {
                    let message: String
                    if potentiallyMaliciousSnodes.count == 1 {
                        message = String(format: NSLocalizedString("dialog_clear_all_data_deletion_failed_1", comment: ""), potentiallyMaliciousSnodes[0])
                    } else {
                        message = String(format: NSLocalizedString("dialog_clear_all_data_deletion_failed_2", comment: ""), String(potentiallyMaliciousSnodes.count), potentiallyMaliciousSnodes.joined(separator: ", "))
                    }
                    let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: NSLocalizedString("BUTTON_OK", comment: ""), style: .default, handler: nil))
                    self?.presentAlert(alert)
                }
            }.catch(on: DispatchQueue.main) { error in
                self?.dismiss(animated: true, completion: nil) // Dismiss the loader
                let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: NSLocalizedString("BUTTON_OK", comment: ""), style: .default, handler: nil))
                self?.presentAlert(alert)
            }
        }
    }
}
