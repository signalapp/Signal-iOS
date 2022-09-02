// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

public class Modal: BaseVC, UIGestureRecognizerDelegate {
    private static let cornerRadius: CGFloat = 11
    
    private let afterClosed: (() -> ())?
    
    // MARK: - Components
    
    lazy var dimmingView: UIView = {
        let result = UIVisualEffectView()
        
        ThemeManager.onThemeChange(observer: result) { [weak result] theme, _ in
            result?.effect = UIBlurEffect(
                style: (theme.interfaceStyle == .light ?
                    UIBlurEffect.Style.systemUltraThinMaterialLight :
                    UIBlurEffect.Style.systemUltraThinMaterial
                )
            )
        }
        
        return result
    }()
    
    lazy var containerView: UIView = {
        let result: UIView = UIView()
        result.clipsToBounds = false
        result.themeBackgroundColor = .alert_background
        result.themeShadowColor = .black
        result.layer.cornerRadius = Modal.cornerRadius
        result.layer.shadowRadius = 10
        result.layer.shadowOpacity = 0.4
        
        return result
    }()
    
    lazy var contentView: UIView = {
        let result: UIView = UIView()
        result.clipsToBounds = true
        result.layer.cornerRadius = Modal.cornerRadius
        
        return result
    }()
    
    lazy var cancelButton: UIButton = {
        let result: UIButton = Modal.createButton(title: "cancel".localized(), titleColor: .textPrimary)
        result.addTarget(self, action: #selector(close), for: .touchUpInside)
                
        return result
    }()
    
    // MARK: - Lifecycle
    
    public init(afterClosed: (() -> ())? = nil) {
        self.afterClosed = afterClosed
        
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("Use init(afterClosed:) instead")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        // Need to remove the background color which is added by the BaseVC
        view.themeBackgroundColor = .clear
        
        view.addSubview(dimmingView)
        view.addSubview(containerView)
        
        containerView.addSubview(contentView)
        
        dimmingView.pin(to: view)
        contentView.pin(to: containerView)
        
        if UIDevice.current.isIPad {
            containerView.set(.width, to: Values.iPadModalWidth)
            containerView.center(in: view)
        }
        else {
            containerView.leadingAnchor
                .constraint(equalTo: view.leadingAnchor, constant: Values.veryLargeSpacing)
                .isActive = true
            view.trailingAnchor
                .constraint(equalTo: containerView.trailingAnchor, constant: Values.veryLargeSpacing)
                .isActive = true
            containerView.center(.vertical, in: view)
        }
        
        // Gestures
        let swipeGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(close))
        swipeGestureRecognizer.direction = .down
        dimmingView.addGestureRecognizer(swipeGestureRecognizer)
        
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(close))
        tapGestureRecognizer.delegate = self
        dimmingView.addGestureRecognizer(tapGestureRecognizer)
        
        populateContentView()
    }
    
    /// To be overridden by subclasses.
    func populateContentView() {
        preconditionFailure("populateContentView() is abstract and must be overridden.")
    }
    
    static func createButton(title: String, titleColor: ThemeValue) -> UIButton {
        let result: UIButton = UIButton()
        result.titleLabel?.font = .systemFont(ofSize: Values.mediumFontSize, weight: UIFont.Weight(600))
        result.setTitle(title, for: .normal)
        result.setThemeTitleColor(titleColor, for: .normal)
        result.setThemeBackgroundColor(.alert_buttonBackground, for: .normal)
        result.setThemeBackgroundColor(.alert_buttonHighlight, for: .highlighted)
        result.set(.height, to: Values.alertButtonHeight)
                
        return result
    }
    
    // MARK: - Interaction
    
    @objc func close() {
        // Recursively dismiss all modals (ie. find the first modal presented by a non-modal
        // and get that to dismiss it's presented view controller)
        var targetViewController: UIViewController? = self
        
        while targetViewController?.presentingViewController is Modal {
            targetViewController = targetViewController?.presentingViewController
        }
        
        targetViewController?.presentingViewController?.dismiss(animated: true) { [weak self] in
            self?.afterClosed?()
        }
    }
    
    // MARK: - UIGestureRecognizerDelegate
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let location: CGPoint = touch.location(in: contentView)
        
        return !contentView.point(inside: location, with: nil)
    }
}
