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
    @IBOutlet private weak var organizationTextField: UITextField!
    @IBOutlet private weak var loginButton: UIButton!
    @IBOutlet private weak var spinner: UIActivityIndicatorView!
    @IBOutlet private weak var createAccountButton: UIButton!
    @IBOutlet private weak var orLabel: UILabel!
    
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
        self.organizationTextField.placeholder = NSLocalizedString("Enter Organization (Optional)", comment: "")
        self.loginButton.titleLabel?.text = NSLocalizedString("SUBMIT", comment: "")
        self.createAccountButton.titleLabel?.text = NSLocalizedString("CREATE_ACCOUNT_BUTTON", comment: "")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
//        self.navigationController?.navigationBar.isHidden = true
        
//        self.createAccountButton.isEnabled = false
//        self.createAccountButton.alpha = 0.5
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(self)
        
        super.viewWillDisappear(animated)
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
        DispatchQueue.main.async {
            self.performSegue(withIdentifier: "smsAuthSegue", sender: self)
        }
    }
    
    private func proceedWithPasswordAuth() {
        DispatchQueue.main.async {
            self.performSegue(withIdentifier: "passwordAuthSegue", sender: self)
        }
    }
    
    private func proceedWithTOTPAuth() {
        DispatchQueue.main.async {
            self.performSegue(withIdentifier: "totpAuthSegue", sender: self)
        }
    }
    
    // MARK: - Actions
    @IBAction private func onLoginButtonTap(sender: Any) {
        if self.isValidOrg(org: self.organizationTextField.text!) && self.isValidUsername(username: self.usernameTextField.text!) {
            self.startSpinner()
            
            var org = self.organizationTextField.text
            if org?.count == 0 {
                org = "forsta"
            }
            
            CCSMCommManager.requestLogin(self.usernameTextField.text!,
                                         orgName: org!,
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
            DispatchQueue.main.async {
                self.spinner.startAnimating()
                self.loginButton.isEnabled = false
                self.loginButton.alpha = 0.5
                self.createAccountButton.isEnabled = false
                self.createAccountButton.alpha = 0.5
            }
        }
    
    private func stopSpinner() {
        DispatchQueue.main.async {
            self.spinner.stopAnimating()
            self.loginButton.isEnabled = true
            self.loginButton.alpha = 1.0
            
            // TODO: uncomment after implementation
//            self.createAccountButton.isEnabled = true
//            self.createAccountButton.alpha = 1.0
        }
    }
}

extension UIViewController {
    func presentInfoAlert(message: String) {
        DispatchQueue.main.async {
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
        }
    }
}
