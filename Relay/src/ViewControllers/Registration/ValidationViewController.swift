//
//  ValidationViewController.swift
//  Forsta
//
//  Created by Mark Descalzo on 5/30/18.
//  Copyright © 2018 Forsta. All rights reserved.
//

import UIKit
import CocoaLumberjack

enum AuthType: Int {
    case sms = 1
    case password = 2
    case totp = 3
}

class ValidationViewController: UITableViewController {
    
    var authType: AuthType = .sms
    
    @IBOutlet private weak var validationCode1TextField: UITextField!
    @IBOutlet private weak var validationCode2TextField: UITextField!
    @IBOutlet private weak var submitButton: UIButton!
    @IBOutlet private weak var spinner: UIActivityIndicatorView!
    @IBOutlet private weak var resendCodeButton: UIButton!
    @IBOutlet private weak var infoLabel: UILabel!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        

    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.navigationController?.navigationBar.isHidden = false
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(updateInfoLabelWithNotification),
                                               name: NSNotification.Name(rawValue: FLRegistrationStatusUpdateNotification),
                                               object: nil)
        self.infoLabel.text = ""
        
        switch self.authType {
        case .sms:
            self.configForSMSAuth()
        case .password:
            self.configForPasswordAuth()
        case .totp:
            self.configForTOTPAuth()
        }
        
        self.submitButton.titleLabel?.text = NSLocalizedString("SUBMIT_BUTTON_LABEL", comment: "")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.validationCode1TextField.resignFirstResponder()
        self.validationCode2TextField.resignFirstResponder()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(self)
        super.viewDidDisappear(animated)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - Setup
    private func configForSMSAuth() {
        self.validationCode1TextField.placeholder = NSLocalizedString("ENTER_VALIDATION_CODE", comment: "")
        self.validationCode1TextField.isSecureTextEntry = false
        self.validationCode1TextField.keyboardType = .numberPad
        self.resendCodeButton.setTitle(NSLocalizedString("RESEND_CODE", comment: ""), for: .normal)
        self.resendCodeButton.isEnabled = true
        self.resendCodeButton.isHidden = false
    }

    private func configForPasswordAuth() {
        self.validationCode1TextField.placeholder = NSLocalizedString("ENTER_PASSWORD", comment: "")
        self.validationCode1TextField.keyboardType = .default
        self.validationCode1TextField.isSecureTextEntry = true
        self.resendCodeButton.setTitle(NSLocalizedString("FORGOT_PASSWORD", comment: ""), for: .normal)
        self.resendCodeButton.isEnabled = true
        self.resendCodeButton.isHidden = false
    }

    private func configForTOTPAuth() {
        self.validationCode1TextField.placeholder = NSLocalizedString("ENTER_PASSWORD", comment: "")
        self.validationCode1TextField.keyboardType = .default
        self.validationCode1TextField.isSecureTextEntry = true
        self.validationCode2TextField.placeholder = NSLocalizedString("ENTER_VALIDATION_CODE", comment: "")
        self.validationCode2TextField.isSecureTextEntry = false
        self.validationCode2TextField.keyboardType = .numberPad
        self.resendCodeButton.setTitle(NSLocalizedString("FORGOT_PASSWORD", comment: ""), for: .normal)
        self.resendCodeButton.isEnabled = true
        self.resendCodeButton.isHidden = false
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.row == 3 {
            if self.authType == .totp {
                return super .tableView(tableView, heightForRowAt: indexPath)
            } else {
                return 0
            }
        } else {
            return super .tableView(tableView, heightForRowAt: indexPath)
        }
    }

    // MARK: - Navigation
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "mainSegue" {
            // Save the passwordAuth property
            
            DispatchQueue.main.async {
                let snc = segue.destination as! SignalsNavigationController
                let appDelegate = UIApplication.shared.delegate as! AppDelegate
                appDelegate.window?.rootViewController = snc
                
                // TODO: Validate this step is necessary
                appDelegate.applicationDidBecomeActive(UIApplication.shared)
            }
        }
    }
    
    private func proceedToMain() {
        DispatchQueue.global(qos: .default).async {
            TSSocketManager.requestSocketOpen()
            CCSMCommManager.refreshCCSMData()
        }
        self.performSegue(withIdentifier: "mainSegue", sender: self)
    }
    
    
    
    // MARK: - Actions
    @IBAction func onValidationButtonTap(sender: Any) {
        self.startSpinner()
        
        DispatchQueue.main.async {
            self.infoLabel.text = NSLocalizedString("Validating...", comment: "")
        }
        
        let orgName = CCSMStorage.sharedInstance().getOrgName()!
        let userName = CCSMStorage.sharedInstance().getUserName()!
        // Password Auth required
        var payload: NSDictionary
        
        switch self.authType {
        case .sms:
            payload = [ "authtoken": "\(orgName):\(userName):\(self.validationCode1TextField.text!)" ]
        case .password:
            payload = [ "fq_tag": "@\(userName):\(orgName)",
                "password": self.validationCode1TextField.text! ]
        case .totp:
            payload = [ "fq_tag": "@\(userName):\(orgName)",
                "password": self.validationCode1TextField.text!,
                "otp" : self.validationCode2TextField.text! ]
       }
        
        CCSMCommManager.authenticate(withPayload: payload as! [AnyHashable : Any]) { (success, error) in
            self.updateInfoLabel(string: "")
            
            if success {
                self.ccsmValidationSucceeded()
            } else {
                Logger.info("Password Validation failed with error: \(String(describing: error?.localizedDescription))")
                self.stopSpinner()
                self.ccsmValidationFailed()
            }
        }

    }
    
    @IBAction func onResendCodeButtonTap(sender: Any) {
        switch self.authType {
        case .sms:
            self.smsResend()
        case .password:
            self.forgotPassword()
        case .totp:
            self.forgotPassword()
        }
    }
    
    // MARK: - Comms
    private func smsResend() {
        CCSMCommManager.requestLogin(CCSMStorage.sharedInstance().getUserName(),
                                     orgName: CCSMStorage.sharedInstance().getOrgName(),
                                     success: {
                                        Logger.info("Request for code resend succeeded.")
                                        DispatchQueue.main.async {
                                            self.validationCode1TextField.text = ""
                                        }
        },
                                     failure: { error in
                                        Logger.debug("Request for code resend failed.  Error: \(String(describing: error?.localizedDescription))");
        })

    }
    
    private func forgotPassword() {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: NSLocalizedString("RESETTING_PASSWORD", comment: ""), message: NSLocalizedString("ARE_YOU_SURE", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("NO", comment: ""), style: .default, handler: nil))
            alert.addAction(UIAlertAction(title: NSLocalizedString("YES", comment: ""), style: .destructive, handler: { (action) in
                
                CCSMCommManager.requestPasswordReset(forUser: CCSMStorage.sharedInstance().getUserName(),
                                                     org: CCSMStorage.sharedInstance().getOrgName(),
                                                     completion: { (success, error) in
                                                        if success {
                                                            Logger.info("Password reset request successful sent.")
                                                            self.presentAlertWithMessage(message: "Password reset request successful.\nPlease check your email or SMS for instructions.")
                                                        } else {
                                                            Logger.debug("Password reset request failed with error:\(String(describing: error?.localizedDescription))")
                                                            self.presentAlertWithMessage(message: "Password reset request failed.\n\(String(describing: error?.localizedDescription))")
                                                        }
                })
            }))
            self.navigationController?.present(alert, animated: true, completion: nil)
        }
    }
    
    private func ccsmValidationSucceeded() {
        // Check if registered and proceed to next storyboard accordingly
        if TSAccountManager.isRegistered() {
            // We are, move onto main
            DispatchQueue.main.async {
                self.infoLabel.text = NSLocalizedString("This device is already registered.", comment: "")
            }
            self.proceedToMain()
        } else {
            FLDeviceRegistrationService.sharedInstance().registerWithTSS { error in
                if error == nil {
                    // Success!
                    self.proceedToMain()
                } else {
                    let err = error! as NSError
                    if err.domain == NSCocoaErrorDomain && err.code == NSUserActivityRemoteApplicationTimedOutError {
                        // Device provision timed out.
                        Logger.info("Device Autoprovisioning timed out.");
                        let alert = UIAlertController(title: NSLocalizedString("REGISTRATION_ERROR", comment: ""),
                                                      message: NSLocalizedString("PROVISION_FAILURE_MESSAGE", comment: ""),
                                                      preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: NSLocalizedString("TXT_CANCEL_TITLE", comment: ""),
                                                      style: .cancel,
                                                      handler: nil))
                        alert.addAction(UIAlertAction(title: NSLocalizedString("TRY_AGAIN", comment: ""),
                                                      style: .default,
                                                      handler: { action in
                                                        self.onValidationButtonTap(sender: self)
                        }))
                        alert.addAction(UIAlertAction(title: NSLocalizedString("REGISTER_FAILED_FORCE_REGISTRATION", comment: ""),
                                                      style: .destructive,
                                                      handler: { action in
                                                        let verifyAlert = UIAlertController(title: nil,
                                                                                            message: NSLocalizedString("REGISTER_FORCE_VALIDATION", comment: ""),
                                                                                            preferredStyle: .alert)
                                                        verifyAlert.addAction(UIAlertAction(title:NSLocalizedString("YES", comment: ""),
                                                                                            style: .destructive,
                                                                                            handler: { action in
                                                                                                self.startSpinner()
                                                                                                FLDeviceRegistrationService.sharedInstance().forceRegistration(completion: { provisionError in
                                                                                                    if provisionError == nil {
                                                                                                        Logger.info("Force registration successful.")
                                                                                                        self.proceedToMain()
                                                                                                    } else {
                                                                                                        Logger.error("Force registration failed with error: \(String(describing: provisionError?.localizedDescription))");
                                                                                                        self.stopSpinner()
                                                                                                        self.presentAlertWithMessage(message: "Forced provisioning failed.  Please try again.")
                                                                                                    }
                                                                                                })
                                                        }))
                                                        verifyAlert.addAction(UIAlertAction(title: NSLocalizedString("NO", comment: ""),
                                                                                            style: .default,
                                                                                            handler: { action in
                                                                                                // User Bailed
                                                                                                self.stopSpinner()
                                                        }))
                                                        DispatchQueue.main.async {
                                                            self.navigationController?.present(verifyAlert, animated: true, completion: {
                                                                self.infoLabel.text = ""
                                                                self.stopSpinner()
                                                            })
                                                        }
                        }))
                        DispatchQueue.main.async {
                            self.navigationController?.present(alert, animated: true, completion: {
                                self.infoLabel.text = ""
                                self.stopSpinner()
                            })
                        }
                        
                        
                    } else {
                        Logger.error("TSS Validation error: \(String(describing: error?.localizedDescription))");
                        DispatchQueue.main.async {
                            // TODO: More user-friendly alert here
                            let alert = UIAlertController(title: NSLocalizedString("REGISTRATION_ERROR", comment: ""),
                                                          message: NSLocalizedString("REGISTRATION_CONNECTION_FAILED", comment: ""),
                                                          preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
                                                          style: .default,
                                                          handler: nil))
                            self.navigationController?.present(alert, animated: true, completion: {
                                self.infoLabel.text = ""
                                self.stopSpinner()
                            })
                        }
                    }
                }
            }
        }
    }
    
    private func ccsmValidationFailed() {
        self.presentAlertWithMessage(message: NSLocalizedString("Invalid credentials.  Please try again.", comment: ""))
    }
    
    // MARK: - Notificaton handling
    @objc func updateInfoLabelWithNotification(notification: Notification) {
        let payload = notification.object as! NSDictionary
        let messageString = payload["message"] as! String
        
        if messageString.count == 0 {
            Logger.warn("Empty registration status notification received.  Ignoring.")
        } else {
            self.updateInfoLabel(string: messageString)
        }
    }
    
    func updateInfoLabel(string: String) {
        DispatchQueue.main.async {
            self.infoLabel.text = string
        }
    }
    
    
    // MARK: - Helper methods
    private func startSpinner() {
        DispatchQueue.main.async {
            self.spinner.startAnimating()
            self.submitButton.isEnabled = false
            self.submitButton.alpha = 0.5
        }
    }
    
    private func stopSpinner() {
        DispatchQueue.main.async {
            self.spinner.stopAnimating()
            self.submitButton.isEnabled = true
            self.submitButton.alpha = 1.0
        }
    }
    
    private func presentAlertWithMessage(message: String) {
        DispatchQueue.main.async {
            let alertView = UIAlertController(title: nil,
                                              message: message,
                                              preferredStyle: .alert)
            
            let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""),
                                         style: .default,
                                         handler: nil)
            alertView.addAction(okAction)
            self.navigationController?.present(alertView, animated: true, completion: nil)
        }
    }
}
