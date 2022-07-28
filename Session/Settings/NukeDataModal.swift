// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit
import SessionSnodeKit
import SessionMessagingKit
import SignalUtilitiesKit

@objc(LKNukeDataModal)
final class NukeDataModal: Modal {
    
    // MARK: - Components
    
    private lazy var titleLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.text = "modal_clear_all_data_title".localized()
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.textAlignment = .center
        
        return result
    }()
    
    private lazy var explanationLabel: UILabel = {
        let result = UILabel()
        result.textColor = Colors.text.withAlphaComponent(Values.mediumOpacity)
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.text = "modal_clear_all_data_explanation".localized()
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
        result.setTitle("TXT_DELETE_TITLE".localized(), for: UIControl.State.normal)
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
        result.setTitle("modal_clear_all_data_device_only_button_title".localized(), for: UIControl.State.normal)
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
        result.setTitle("modal_clear_all_data_entire_account_button_title".localized(), for: UIControl.State.normal)
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
    
    private lazy var contentStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ titleLabel, explanationLabel ])
        result.axis = .vertical
        result.spacing = Values.largeSpacing
        
        return result
    }()
    
    private lazy var mainStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ contentStackView, buttonStackViewContainer ])
        result.axis = .vertical
        result.spacing = Values.largeSpacing - Values.smallFontSize / 2
        
        return result
    }()
    
    // MARK: - Lifecycle
    
    override func populateContentView() {
        contentView.addSubview(mainStackView)
        mainStackView.pin(.leading, to: .leading, of: contentView, withInset: Values.largeSpacing)
        mainStackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: mainStackView, withInset: Values.largeSpacing)
        contentView.pin(.bottom, to: .bottom, of: mainStackView, withInset: mainStackView.spacing)
    }
    
    // MARK: - Interaction
    
    @objc private func clearAllData() {
        UIView.animate(withDuration: 0.25) {
            self.buttonStackView1.alpha = 0
            self.buttonStackView2.alpha = 1
        }
        
        UIView.transition(
            with: explanationLabel,
            duration: 0.25,
            options: .transitionCrossDissolve,
            animations: {
                self.explanationLabel.text = "modal_clear_all_data_explanation_2".localized()
            },
            completion: nil
        )
    }
    
    @objc private func clearDeviceOnly() {
        ModalActivityIndicatorViewController.present(fromViewController: self, canCancel: false) { [weak self] _ in
            Storage.shared
                .writeAsync { db in try MessageSender.syncConfiguration(db, forceSyncNow: true) }
                .ensure(on: DispatchQueue.main) {
                    self?.deleteAllLocalData()
                    self?.dismiss(animated: true, completion: nil) // Dismiss the loader
                }
                .retainUntilComplete()
        }
    }
    
    @objc private func clearEntireAccount() {
        ModalActivityIndicatorViewController
            .present(fromViewController: self, canCancel: false) { [weak self] _ in
                SnodeAPI.clearAllData()
                    .done(on: DispatchQueue.main) { confirmations in
                        self?.dismiss(animated: true, completion: nil) // Dismiss the loader
                        
                        let potentiallyMaliciousSnodes = confirmations.compactMap { $0.value == false ? $0.key : nil }
                        
                        if potentiallyMaliciousSnodes.isEmpty {
                            self?.deleteAllLocalData()
                        }
                        else {
                            let message: String
                            if potentiallyMaliciousSnodes.count == 1 {
                                message = String(format: "dialog_clear_all_data_deletion_failed_1".localized(), potentiallyMaliciousSnodes[0])
                            }
                            else {
                                message = String(format: "dialog_clear_all_data_deletion_failed_2".localized(), String(potentiallyMaliciousSnodes.count), potentiallyMaliciousSnodes.joined(separator: ", "))
                            }
                            
                            let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "BUTTON_OK".localized(), style: .default, handler: nil))
                            
                            self?.presentAlert(alert)
                        }
                    }
                    .catch(on: DispatchQueue.main) { error in
                        self?.dismiss(animated: true, completion: nil) // Dismiss the loader
                        
                        let alert = UIAlertController(title: "Error", message: error.localizedDescription, preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "BUTTON_OK".localized(), style: .default, handler: nil))
                        self?.presentAlert(alert)
                    }
            }
    }
    
    private func deleteAllLocalData() {
        // Unregister push notifications if needed
        let isUsingFullAPNs: Bool = UserDefaults.standard[.isUsingFullAPNs]
        let maybeDeviceToken: String? = UserDefaults.standard[.deviceToken]
        
        if isUsingFullAPNs, let deviceToken: String = maybeDeviceToken {
            let data: Data = Data(hex: deviceToken)
            PushNotificationAPI.unregister(data).retainUntilComplete()
        }
        
        // Clear the app badge and notifications
        AppEnvironment.shared.notificationPresenter.clearAllNotifications()
        CurrentAppContext().setMainAppBadgeNumber(0)
        
        // Clear out the user defaults
        UserDefaults.removeAll()
        
        // Remove the cached key so it gets re-cached on next access
        General.cache.mutate { $0.encodedPublicKey = nil }
        
        // Clear the Snode pool
        SnodeAPI.clearSnodePool()
        
        // Stop any pollers
        (UIApplication.shared.delegate as? AppDelegate)?.stopPollers()
        
        // Call through to the SessionApp's "resetAppData" which will wipe out logs, database and
        // profile storage
        let wasUnlinked: Bool = UserDefaults.standard[.wasUnlinked]
        
        SessionApp.resetAppData {
            // Resetting the data clears the old user defaults. We need to restore the unlink default.
            UserDefaults.standard[.wasUnlinked] = wasUnlinked
        }
    }
}
