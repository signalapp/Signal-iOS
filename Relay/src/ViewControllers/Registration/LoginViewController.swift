//
//  LoginViewController.swift
//  Forsta
//
//  Created by Mark Descalzo on 6/1/18.
//  Copyright © 2018 Forsta. All rights reserved.
//

import UIKit

class LoginViewController: UITableViewController {

    @IBOutlet private weak var usernameTextField: UITextField!
    @IBOutlet private weak var loginButton: UIButton!
    @IBOutlet private weak var spinner: UIActivityIndicatorView!
    @IBOutlet private weak var createAccountButton: UIButton!
    @IBOutlet private weak var orLabel: UILabel!
    
    private var orgString: String {
        get {
            if let userOrgString = self.usernameTextField.text {
                if let firstColonIndex = userOrgString.firstIndex(of: ":") {
                    let orgIndex = userOrgString.index(firstColonIndex, offsetBy: 1)
                    let org = userOrgString.suffix(from: orgIndex)
                    if org.count > 0 {
                        return String(org)
                    }
                }
            }
            return "forsta"
        }
    }
    private var usernameString: String {
        get {
            if let userOrgString = self.usernameTextField.text {
                let strippedString = userOrgString.trimmingCharacters(in: CharacterSet(["@"]))
                let firstColonIndex = strippedString.firstIndex(of: ":") ?? strippedString.endIndex
                let user = strippedString.prefix(upTo: firstColonIndex)
                if user.count > 0 {
                    return String(user)
                }
            }
            return ""
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Navigation bar setup
        let navBar = self.navigationController?.navigationBar
        navBar?.barTintColor = UIColor.white
        navBar?.tintColor = UIColor.black
        navBar?.shadowImage = UIImage()
        navBar?.isTranslucent = false
        
        // Localize the things
        self.usernameTextField.placeholder = NSLocalizedString("ENTER_USERNAME_LABEL", comment: "")
        self.loginButton.titleLabel?.text = NSLocalizedString("SUBMIT", comment: "")
        self.createAccountButton.titleLabel?.text = NSLocalizedString("CREATE_ACCOUNT_BUTTON", comment: "")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        NotificationCenter.default.addObserver(self,
                                               selector:#selector(updateLoginButton),
                                               name: NSNotification.Name.UITextFieldTextDidChange,
                                               object: nil)
        self.updateLoginButton()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(self)

        super.viewDidDisappear(animated)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "smsAuthSegue" {
            let vc = segue.destination as! ValidationViewController
            vc.authType = .sms
        } else if segue.identifier == "passwordAuthSegue" {
            let vc = segue.destination as! ValidationViewController
            vc.authType = .password
        } else if segue.identifier == "totpAuthSegue" {
            let vc = segue.destination as! ValidationViewController
            vc.authType = .totp
        }
    }
    
    private func proceedWithSMSAuth() {
        DispatchMainThreadSafe({
            self.performSegue(withIdentifier: "smsAuthSegue", sender: self)
        })
    }
    
    private func proceedWithPasswordAuth() {
        DispatchMainThreadSafe({
            self.performSegue(withIdentifier: "passwordAuthSegue", sender: self)
        })
    }
    
    private func proceedWithTOTPAuth() {
        DispatchMainThreadSafe({
            self.performSegue(withIdentifier: "totpAuthSegue", sender: self)
        })
    }
    
    // MARK: - Actions
    @IBAction private func onLoginButtonTap(sender: Any) {
        if self.isValidOrg(org: orgString) && self.isValidUsername(username: usernameString) {
            self.startSpinner()
            
            CCSMCommManager.requestLogin(usernameString,
                                         orgName: orgString,
                                         success: {
                                            self.stopSpinner()
                                            self.proceedWithSMSAuth()
            },
                                         failure: { error in
                                            self.stopSpinner()
                                            if (error?.localizedDescription.contains("password auth required"))! {
                                                if (error?.localizedDescription.contains("totp auth required"))! {
                                                    self.proceedWithTOTPAuth()
                                                } else {
                                                    self.proceedWithPasswordAuth()
                                                }
                                            } else {
                                                self.presentInfoAlert(message: (error?.localizedDescription)!)
                                            }
            })
        } else {
            self.presentInfoAlert(message: NSLocalizedString("USERNAME_ORG_ERROR", comment: ""))
        }
    }
    
    // MARK: - Notification handler(s)
    @objc func updateLoginButton() {
        if self.usernameTextField.text!.count > 0 {
            self.loginButton.enable()
        } else {
            self.loginButton.disable()
        }
    }

    
    // MARK: - Helpers
    private func isValidOrg(org: String) -> Bool {
        // TODO: Someday apply regex here for more thorough validation
//        return (org.count > 0)
        return true
    }
    
    private func isValidUsername(username: String) -> Bool {
        // TODO: Someday apply regex here for more thorough validation
        return (username.count > 0)
    }
    
    private func startSpinner() {
        DispatchMainThreadSafe({
            self.spinner.startAnimating()
            self.loginButton.disable()
            self.createAccountButton.disable()
        })
    }
    
    private func stopSpinner() {
        DispatchMainThreadSafe({
            self.spinner.stopAnimating()
            self.loginButton.enable()
            self.createAccountButton.enable()
        })
    }
}

extension LoginViewController : UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
      
        if !string.isEmpty {
            if Array(string)[0] == "@" {
                if range.location == 0 {
                    return true
                } else {
                    return false
                }
            }
        }
        
        if string.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            return false
        }
        
        return true
    }
}

extension UIViewController {
    func presentInfoAlert(message: String) {
        DispatchMainThreadSafe({
            let alert = UIAlertController(title: nil,
                                          message: message,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
                                          style: .default,
                                          handler: nil))
            if (self.navigationController != nil) {
                self.navigationController?.present(alert, animated: true, completion: nil)
            } else if self.tabBarController != nil {
                self.tabBarController?.present(alert, animated: true, completion: nil)
            }
        })
    }
}

