//
//  NewAccountViewController.swift
//  Forsta
//
//  Created by Mark Descalzo on 5/2/18.
//  Copyright © 2018 Forsta. All rights reserved.
//

import UIKit
import ReCaptcha
import CocoaLumberjack

class NewAccountViewController: UITableViewController, UITextFieldDelegate {
    
    
    @IBOutlet weak var nameTextField: UITextField!
    @IBOutlet weak var usernameTextField: UITextField!
    @IBOutlet weak var mobileNumberTextField: UITextField!
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var password1TextField: UITextField!
    @IBOutlet weak var password2TextField: UITextField!
    @IBOutlet weak var infoLabel: UILabel!
    
    @IBOutlet weak var submitButton: UIButton!
    @IBOutlet weak var spinner: UIActivityIndicatorView!
    
    private var simplePhoneNumber: NSString = ""
    
    private lazy var inputFields: Array<UITextField>! = [ self.nameTextField,
                                                          self.usernameTextField,
                                                          self.emailTextField,
                                                          self.mobileNumberTextField,
                                                          self.password1TextField,
                                                          self.password2TextField ]
    
    private var recaptcha: ReCaptcha!
    
    private let recaptchaWebViewTag = 123
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.nameTextField.placeholder = NSLocalizedString("Enter Name", comment: "")
        self.usernameTextField.placeholder = NSLocalizedString("Enter Username", comment: "")
        self.mobileNumberTextField.placeholder = NSLocalizedString("Enter Phone Number (Optional)", comment: "")
        self.emailTextField.placeholder = NSLocalizedString("Enter Email Address", comment: "")
        self.password1TextField.placeholder = NSLocalizedString("Enter Password", comment: "")
        self.password2TextField.placeholder = NSLocalizedString("Confirm Password", comment: "")
        self.submitButton.setTitle(NSLocalizedString("SUBMIT", comment: ""), for: .normal)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.navigationController?.navigationBar.isHidden = false
        self.updateSubmitButton()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.hideKeyboard()
        
        super.viewDidAppear(animated)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    // MARK: - Actions
    @IBAction func textFieldDidChange(textField: UITextField) {
        self.updateSubmitButton()
    }
    
    @IBAction func didPressSubmit(_ sender: UIButton) {
        
        self.startSpinner()
        self.updateInfoLabel(text: NSLocalizedString("Creating new account...", comment: ""))
        self.setupReCaptcha()
        
        // Make the recaptcha call...
        self.recaptcha.validate(on: self.view,
                                completion: { (result: ReCaptchaResult) in
                                    
                                    var token: String?
                                    do {
                                        token = try result.dematerialize()
                                    } catch {
                                        DDLogDebug("Error retrieving token.")
                                    }
                                    
                                    // remove the recaptcha webview
                                    DispatchQueue.main.async {
                                        self.view.viewWithTag(self.recaptchaWebViewTag)?.removeFromSuperview()
                                    }
                                    
                                    // make the account creation request
                                    CCSMCommManager.requestPasswordAccountCreation(withFullName: self.nameTextField.text!,
                                                                                   tagSlug: self.usernameTextField.text!,
                                                                                   password: self.password1TextField.text!,
                                                                                   email: self.emailTextField.text!,
                                                                                   phone: ((self.mobileNumberTextField.text?.count)! > 0 ? "+1\(String(describing: self.simplePhoneNumber))" : ""),
                                                                                   token: token!,
                                                                                   completion: { (success, error, payload) in
                                                                                    self.stopSpinner()
                                                                                    
                                                                                    if success {
                                                                                        self.updateInfoLabel(text: NSLocalizedString("Account creation successful!", comment: ""))
                                                                                        self.accountCreationSucceeded()
                                                                                    } else {
                                                                                        self.updateInfoLabel(text: "")
                                                                                        let dictionary = payload! as NSDictionary
                                                                                        
                                                                                        var title: String = ""
                                                                                        var message: String = ""
                                                                                        
                                                                                        let keys = dictionary.allKeys as! Array<String>
                                                                                        if keys.last  == "phone" {
                                                                                            title = NSLocalizedString("Invalid mobile number", comment: "")
                                                                                            let messages = (dictionary.object(forKey: keys.last!) as? Array<String>)!
                                                                                            message = messages.last!
                                                                                        } else if keys.last == "email" {
                                                                                            title = NSLocalizedString("Invalid email address", comment: "")
                                                                                            let messages = (dictionary.object(forKey: keys.last!) as? Array<String>)!
                                                                                            message = messages.last!
                                                                                        } else if keys.last == "fullname" {
                                                                                            title = NSLocalizedString("Invalid name", comment: "")
                                                                                            let messages = (dictionary.object(forKey: keys.last!) as? Array<String>)!
                                                                                            message = messages.last!
                                                                                        } else if keys.last == "tag_slug" {
                                                                                            title = NSLocalizedString("Invalid username", comment: "")
                                                                                            let messages = (dictionary.object(forKey: keys.last!) as? Array<String>)!
                                                                                            message = messages.last!
                                                                                        } else if keys.last == "password" {
                                                                                            title = NSLocalizedString("Invalid password", comment: "")
                                                                                            let messages = (dictionary.object(forKey: keys.last!) as? Array<String>)!
                                                                                            message = messages.last!
                                                                                        } else {
                                                                                            DDLogDebug((error?.localizedDescription)!)
                                                                                            message = String(format: "%@\n\n%@", NSLocalizedString("REGISTER_CREATION_FAILURE", comment: ""), (error?.localizedDescription)!)
                                                                                        }
                                                                                        self.presentAlertWithMessage(title: title, message: message)
                                                                                        self.recaptcha.reset()
                                                                                    }
                                    })
        })
        
        // This is the SMS auth call
        //                                        let payload = [ "first_name" : self.firstNameTextField.text!,
        //                                                        "last_name" : self.lastNameTextField.text!,
        //                                                        "phone" : String(format: "+1%@", self.simplePhoneNumber),
        //                                                        "email" : self.emailTextField.text! ]
        //
        //                                        CCSMCommManager.requestAccountCreation(withUserDict: payload,
        //                                                                               token: token!,
        //                                                                               completion: { (success, error) in
        //
        //                                                                                self.stopSpinner()
        //                                                                                if success {
        //                                                                                    DispatchQueue.main.async {
        //                                                                                        self.performSegue(withIdentifier: "validationViewSegue", sender: self)
        //                                                                                    }
        //                                                                                } else {
        //                                                                                    DispatchQueue.main.async {
        //                                                                                        DDLogDebug((error?.localizedDescription)!)
        //                                                                                        let message: String = String(format: "%@\n\n%@", NSLocalizedString("REGISTER_CREATION_FAILURE", comment: ""), (error?.localizedDescription)!)
        //                                                                                        self.presentAlertWithMessage(message: message)
        //                                                                                        self.recaptcha.reset()
        //                                                                                    }
        //                                                                                }
        //                                        })
        //            })
    }
    
    
    // MARK: - Navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "mainSegue" {
            // Save the passwordAuth property
            Environment.preferences().passwordAuth = true;
            
            DispatchQueue.main.async {
                let snc = segue.destination as! NavigationController
                let appDelegate = UIApplication.shared.delegate as! AppDelegate
                appDelegate.window.rootViewController = snc
                
                // TODO: Validate this step is necessary
                appDelegate.applicationDidBecomeActive(UIApplication.shared)
            }
        }
    }
    
    private func proceedToMain() {
        DispatchQueue.global(qos: .default).async {
            TSSocketManager.becomeActiveFromForeground()
            CCSMCommManager.refreshCCSMData()
        }
        self.performSegue(withIdentifier: "mainSegue", sender: self)
    }
    
    
    // MARK: - Helper methods
    private func accountCreationSucceeded() {
        
        // authenticate with new account creds
        let orgName = CCSMStorage.sharedInstance().getOrgName()!
        let userName = CCSMStorage.sharedInstance().getUserName()!
        
        self.updateInfoLabel(text: NSLocalizedString("Authenticating...", comment: ""))
        
        CCSMCommManager.authenticate(withPayload: [ "fq_tag": "@\(userName):\(orgName)",
            "password": self.password1TextField.text! ]) { (success, error) in
                self.stopSpinner()
                self.updateInfoLabel(text: NSLocalizedString("", comment: ""))
                
                if success {
                    
                    self.updateInfoLabel(text: NSLocalizedString("Registering device.", comment: ""))
                    
                    FLDeviceRegistrationService.sharedInstance().registerWithTSS { error in
                        if error == nil {
                            // Success!
                            self.proceedToMain()
                        } else {
                            DDLogError("TSS Validation error: \(String(describing: error?.localizedDescription))");
                            DispatchQueue.main.async {
                                // TODO: More user-friendly alert here
                                let alert = UIAlertController(title: NSLocalizedString("REGISTRATION_ERROR", comment: ""),
                                                              message: NSLocalizedString("REGISTRATION_CONNECTION_FAILED", comment: ""),
                                                              preferredStyle: .alert)
                                alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""),
                                                              style: .default,
                                                              handler: nil))
                                self.navigationController?.present(alert, animated: true, completion: {
                                    self.updateInfoLabel(text: "")
                                    self.stopSpinner()
                                })
                            }
                        }
                    }
                } else {
                    DDLogInfo("Password Validation failed with error: \(String(describing: error?.localizedDescription))")
                    self.presentAlertWithMessage(title: "Authentication failed.", message: String(describing: error?.localizedDescription))
                }
        }
        
        
    }
    
    private func updateInfoLabel(text: String?) {
        DispatchQueue.main.async {
            self.infoLabel.text = text
        }
    }
    
    private func updateSubmitButton() {
        if ((self.nameTextField.text?.count)! > 0 &&
            (self.usernameTextField.text?.count)! > 0 &&
            (((self.mobileNumberTextField.text?.count)! == 14) || ((self.mobileNumberTextField.text?.count)! == 0)) &&
            self.validateEmailString(strEmail: self.emailTextField.text!) &&
            (self.password1TextField.text?.count)! > 7 &&
            self.password1TextField.text == self.password2TextField.text)
        {
            DispatchQueue.main.async {
                self.submitButton.isEnabled = true
                self.submitButton.alpha = 1.0
            }
        } else {
            DispatchQueue.main.async {
                self.submitButton.isEnabled = false
                self.submitButton.alpha = 0.5
            }
        }
    }
    
    private func hideKeyboard() {
        DispatchQueue.main.async {
            for textField in self.inputFields {
                textField.resignFirstResponder()
            }
        }
    }
    
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
    
    private func presentAlertWithMessage(title: String, message: String) {
        DispatchQueue.main.async {
            let alertView = UIAlertController(title: title,
                                              message: message,
                                              preferredStyle: .alert)
            
            let okAction = UIAlertAction(title: NSLocalizedString("OK", comment: ""),
                                         style: .default,
                                         handler: nil)
            alertView.addAction(okAction)
            self.navigationController?.present(alertView, animated: true, completion: nil)
        }
    }
    
    // Swiped from: https://stackoverflow.com/questions/5428304/email-validation-on-textfield-in-iphone-sdk
    private func validateEmailString(strEmail:String) -> Bool
    {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,4}"
        let emailText = NSPredicate(format:"SELF MATCHES [c]%@",emailRegex)
        return (emailText.evaluate(with: strEmail))
    }
    
    // Setup reCaptha object
    private func setupReCaptcha() {
        self.recaptcha = try! ReCaptcha(apiKey: self.recaptchaSiteKey(), baseURL: self.recaptchaDomain(), endpoint: ReCaptcha.Endpoint.default)
        
        self.recaptcha.configureWebView { webView in
            webView.tag = self.recaptchaWebViewTag
            webView.backgroundColor = UIColor.clear
            
            webView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint(item: webView, attribute: NSLayoutAttribute.centerX, relatedBy: NSLayoutRelation.equal, toItem: self.view, attribute: NSLayoutAttribute.centerX, multiplier: 1, constant: 0).isActive = true
            NSLayoutConstraint(item: webView, attribute: NSLayoutAttribute.centerY, relatedBy: NSLayoutRelation.equal, toItem: self.view, attribute: NSLayoutAttribute.centerY, multiplier: 1, constant: 0).isActive = true
            NSLayoutConstraint(item: webView, attribute: NSLayoutAttribute.width, relatedBy: NSLayoutRelation.equal, toItem: self.view, attribute: NSLayoutAttribute.width, multiplier: 1, constant: -80).isActive = true
            NSLayoutConstraint(item: webView, attribute: NSLayoutAttribute.height, relatedBy: NSLayoutRelation.equal, toItem: webView, attribute: NSLayoutAttribute.width, multiplier: 1.6, constant: 0).isActive = true
        }
    }
    
    // Retrieve reCaptcha key from plist
    private func recaptchaSiteKey() -> String {
        var forstaDict: NSDictionary?
        if let path = Bundle.main.path(forResource: "Forsta-values", ofType: "plist") {
            forstaDict = NSDictionary(contentsOfFile: path)
        }
        if let dict = forstaDict {
            return dict.object(forKey: "RECAPTCHA_SITE_KEY") as! String
        } else {
            return ""
        }
    }
    
    // Retrieve reCaptcha domain from plist
    private func recaptchaDomain() -> URL {
        var forstaDict: NSDictionary?
        if let path = Bundle.main.path(forResource: "Forsta-values", ofType: "plist") {
            forstaDict = NSDictionary(contentsOfFile: path)
        }
        if let dict = forstaDict {
            return URL(string: dict.object(forKey: "RECAPTHCA_DOMAIN") as! String)!
        } else {
            return URL(string:"")!
        }
    }
    
    
    // MARK: - UITextfield delegate methods
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // Gracefully cycle through text entry fields on return tap
        let currentIndex = self.inputFields.index(of: textField)
        let nextIndex = (self.inputFields.count > currentIndex! + 1 ? currentIndex! + 1 : 0)
        self.inputFields[nextIndex].becomeFirstResponder()
        
        return true
    }
    
    // Swiped from: https://stackoverflow.com/questions/1246439/uitextfield-for-phone-number
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        var returnValue: Bool = true
        
        if (textField == self.mobileNumberTextField) {
            let oldText: NSString = textField.text! as NSString
            let newText: NSString = oldText.replacingCharacters(in: range, with: string) as NSString
            let deleting: Bool = (newText.length) < (oldText.length)
            self.simplePhoneNumber = newText.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression, range: NSMakeRange(0, newText.length) ) as NSString
            
            let digits = self.simplePhoneNumber.length
            
            if digits > 10 {
                self.simplePhoneNumber = self.simplePhoneNumber.substring(to: 10) as NSString
            }
            
            if digits == 0 {
                textField.text = ""
            } else if (digits < 3 || (digits == 3 && deleting)) {
                textField.text = String(format: "(%@", self.simplePhoneNumber)
            } else if (digits < 6 || (digits == 6 && deleting)) {
                textField.text = String(format: "(%@) %@",
                                        (self.simplePhoneNumber.substring(to: 3)),
                                        (self.simplePhoneNumber.substring(from: 3)))
            } else {
                textField.text = String(format: "(%@) %@-%@",
                                        (self.simplePhoneNumber.substring(to: 3)),
                                        self.simplePhoneNumber.substring(with: NSMakeRange(3, 3)),
                                        (self.simplePhoneNumber.substring(from: 6)))
            }
            self.updateSubmitButton()
            returnValue = false
        }
        return returnValue
    }
}
