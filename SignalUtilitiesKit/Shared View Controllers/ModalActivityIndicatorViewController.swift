//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import MediaPlayer
import SessionUIKit
import NVActivityIndicatorView

// A modal view that be used during blocking interactions (e.g. waiting on response from
// service or on the completion of a long-running local operation).
@objc
public class ModalActivityIndicatorViewController: OWSViewController {
    let canCancel: Bool
    
    let message: String?

    @objc
    public var wasCancelled: Bool = false
    
    private lazy var spinner: NVActivityIndicatorView = {
        let result = NVActivityIndicatorView(frame: CGRect.zero, type: .circleStrokeSpin, color: .white, padding: nil)
        result.set(.width, to: 64)
        result.set(.height, to: 64)
        return result
    }()

    var wasDimissed: Bool = false

    // MARK: Initializers

    @available(*, unavailable, message:"use other constructor instead.")
    public required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    public required init(canCancel: Bool = false, message: String? = nil) {
        self.canCancel = canCancel
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }

    @objc
    public class func present(
        fromViewController: UIViewController?,
        canCancel: Bool = false,
        message: String? = nil,
        backgroundBlock: @escaping (ModalActivityIndicatorViewController) -> Void
    ) {
        guard let fromViewController: UIViewController = fromViewController else { return }
        
        AssertIsOnMainThread()

        let view = ModalActivityIndicatorViewController(canCancel: canCancel, message: message)
        // Present this modal _over_ the current view contents.
        view.modalPresentationStyle = .overFullScreen
        view.modalTransitionStyle = .crossDissolve
        fromViewController.present(view, animated: false) {
            DispatchQueue.global().async {
                backgroundBlock(view)
            }
        }
    }

    @objc
    public func dismiss(completion: @escaping () -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.dismiss(completion: completion)
            }
            return
        }

        if !wasDimissed {
            // Only dismiss once.
            self.dismiss(animated: false, completion: completion)
            wasDimissed = true
        } else {
            // If already dismissed, wait a beat then call completion.
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    public override func loadView() {
        super.loadView()

        self.view.backgroundColor = UIColor(white: 0, alpha: 0.6)
        self.view.isOpaque = false
        
        if let message = message {
            let messageLabel = UILabel()
            messageLabel.text = message
            messageLabel.font = .systemFont(ofSize: Values.mediumFontSize)
            messageLabel.textColor = UIColor.white
            messageLabel.numberOfLines = 0
            messageLabel.textAlignment = .center
            messageLabel.lineBreakMode = .byWordWrapping
            messageLabel.set(.width, to: UIScreen.main.bounds.width - 2 * Values.mediumSpacing)
            let stackView = UIStackView(arrangedSubviews: [ messageLabel, spinner ])
            stackView.axis = .vertical
            stackView.spacing = Values.largeSpacing
            stackView.alignment = .center
            self.view.addSubview(stackView)
            stackView.center(in: self.view)
        } else {
            self.view.addSubview(spinner)
            spinner.autoCenterInSuperview()
        }

        if canCancel {
            let cancelButton = UIButton(type: .custom)
            cancelButton.setTitle(CommonStrings.cancelButton, for: .normal)
            cancelButton.setTitleColor(UIColor.white, for: .normal)
            cancelButton.backgroundColor = UIColor.ows_darkGray
            cancelButton.titleLabel?.font = UIFont.ows_mediumFont(withSize: ScaleFromIPhone5To7Plus(18, 22))
            cancelButton.layer.cornerRadius = ScaleFromIPhone5To7Plus(4, 5)
            cancelButton.clipsToBounds = true
            cancelButton.addTarget(self, action: #selector(cancelPressed), for: .touchUpInside)
            let buttonWidth = ScaleFromIPhone5To7Plus(140, 160)
            let buttonHeight = ScaleFromIPhone5To7Plus(40, 50)
            self.view.addSubview(cancelButton)
            cancelButton.autoHCenterInSuperview()
            cancelButton.autoPinEdge(toSuperviewEdge: .bottom, withInset: 50)
            cancelButton.autoSetDimension(.width, toSize: buttonWidth)
            cancelButton.autoSetDimension(.height, toSize: buttonHeight)
        }

        // Hide the modal until the presentation animation completes.
        self.view.layer.opacity = 0.0
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.spinner.startAnimating()

        // Fade in the modal
        UIView.animate(withDuration: 0.35) {
            self.view.layer.opacity = 1.0
        }
    }

    @objc func cancelPressed() {
        AssertIsOnMainThread()

        wasCancelled = true

        dismiss { }
    }
}
