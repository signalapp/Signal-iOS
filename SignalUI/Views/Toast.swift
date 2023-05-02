//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

@objc
public class ToastController: NSObject, ToastViewDelegate {

    static var currentToastController: ToastController?

    private let toastView: ToastView
    private var isDismissing: Bool

    // MARK: Initializers

    @objc
    required public init(text: String) {
        toastView = ToastView()
        toastView.text = text
        isDismissing = false

        super.init()

        toastView.delegate = self
    }

    // MARK: Public

    public func presentToastView(from edge: ALEdge,
                                 of view: UIView,
                                 inset: CGFloat,
                                 dismissAfter: DispatchTimeInterval = .seconds(4)) {
        owsAssertDebug(edge == .bottom || edge == .top)
        let offset = (edge == .top) ? inset : -inset

        // Add to the first non-scrollview in the hierarchy, but still pin to the original view.
        // We don't want the toast to be a subview of any scrollview or it will be subject to scrolling.
        var parentView = view
        while parentView is UIScrollView, let superview = view.superview {
            parentView = superview
        }

        Logger.debug("")
        toastView.alpha = 0
        parentView.addSubview(toastView)
        toastView.setCompressionResistanceHigh()
        toastView.autoPinEdge(edge, to: edge, of: view, withOffset: offset)
        toastView.autoPinWidthToSuperview(withMargin: 8)

        if let currentToastController = type(of: self).currentToastController {
            currentToastController.dismissToastView()
            type(of: self).currentToastController = nil
        }
        type(of: self).currentToastController = self

        UIView.animate(withDuration: 0.2) {
            self.toastView.alpha = 1
        }

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + dismissAfter) {
            // intentional strong reference to self.
            // As with an AlertController, the caller likely expects toast to
            // be presented and dismissed without maintaining a strong reference to ToastController
            self.dismissToastView()
        }
    }

    // MARK: ToastViewDelegate

    func didTapToastView(_ toastView: ToastView) {
        Logger.debug("")
        self.dismissToastView()
    }

    func didSwipeToastView(_ toastView: ToastView) {
        Logger.debug("")
        self.dismissToastView()
    }

    // MARK: Internal

    func dismissToastView() {
        Logger.debug("")

        guard !isDismissing else {
            return
        }
        isDismissing = true

        if type(of: self).currentToastController == self {
            type(of: self).currentToastController = nil
        }

        UIView.animate(withDuration: 0.2,
                       animations: {
            self.toastView.alpha = 0
        },
                       completion: { (_) in
            self.toastView.removeFromSuperview()
        })
    }
}

protocol ToastViewDelegate: AnyObject {
    func didTapToastView(_ toastView: ToastView)
    func didSwipeToastView(_ toastView: ToastView)
}

class ToastView: UIView {

    var text: String? {
        get {
            return label.text
        }
        set {
            label.text = newValue
        }
    }
    weak var delegate: ToastViewDelegate?

    private let label: UILabel
    private let darkThemeBackgroundOverlay = UIView()

    // MARK: Initializers

    override init(frame: CGRect) {
        label = UILabel()
        super.init(frame: frame)

        self.layer.cornerRadius = 12
        self.clipsToBounds = true
        self.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        if UIAccessibility.isReduceTransparencyEnabled {
            backgroundColor = .ows_blackAlpha80
        } else {
            let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
            addSubview(blurEffectView)
            blurEffectView.autoPinEdgesToSuperviewEdges()
        }

        addSubview(darkThemeBackgroundOverlay)
        darkThemeBackgroundOverlay.autoPinEdgesToSuperviewEdges()
        darkThemeBackgroundOverlay.backgroundColor = UIColor.white.withAlphaComponent(0.10)

        label.textColor = .ows_white
        label.font = UIFont.dynamicTypeBody2
        label.numberOfLines = 0
        self.addSubview(label)
        label.autoPinEdgesToSuperviewMargins()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap(gesture:)))
        self.addGestureRecognizer(tapGesture)

        let swipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(didSwipe(gesture:)))
        self.addGestureRecognizer(swipeGesture)

        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeDidChange, object: nil)
        applyTheme()

    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Gestures

    @objc
    func applyTheme() {
        darkThemeBackgroundOverlay.isHidden = !Theme.isDarkThemeEnabled
    }

    @objc
    func didTap(gesture: UITapGestureRecognizer) {
        self.delegate?.didTapToastView(self)
    }

    @objc
    func didSwipe(gesture: UISwipeGestureRecognizer) {
        self.delegate?.didSwipeToastView(self)
    }
}

// MARK: -

@objc
public extension UIView {
    func presentToast(text: String, fromViewController: UIViewController) {
        fromViewController.presentToast(text: text)
    }
}

// MARK: -

@objc
public extension UIViewController {
    func presentToast(text: String, extraVInset: CGFloat = 0) {
        let toastController = ToastController(text: text)
        // TODO: There should be a better way to do this.
        // TODO: Take into account the keyboard height.
        let bottomInset = view.safeAreaInsets.bottom + 8 + extraVInset
        toastController.presentToastView(from: .bottom, of: view, inset: bottomInset)
    }
}
