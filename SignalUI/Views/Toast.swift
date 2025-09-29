//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import PureLayout
import SignalServiceKit

final public class ToastController: NSObject, ToastViewDelegate {

    static var currentToastController: ToastController?

    private weak var toastView: ToastView?
    private var isDismissing: Bool
    private let toastText: String

    // MARK: Initializers

    public init(text: String) {
        self.toastText = text
        isDismissing = false

        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHide), name: UIResponder.keyboardDidHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidAppear), name: UIResponder.keyboardDidShowNotification, object: nil)
    }

    // MARK: Public

    public func presentToastView(from edge: ALEdge,
                                 of view: UIView,
                                 inset: CGFloat,
                                 dismissAfter: DispatchTimeInterval = .seconds(4)) {
        let toastView = ToastView()
        toastView.text = self.toastText
        toastView.delegate = self
        self.toastView = toastView

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

        self.viewToPinTo = view
        self.offset = offset
        if
            edge == .bottom,
            // If keyboard is closed, its layout guide height is equivalent to the bottom safe area inset.
            view.keyboardLayoutGuide.layoutFrame.height > view.safeAreaInsets.totalHeight
        {
            let constraint = keyboardConstraint(toastView: toastView, viewOwningKeyboard: view)
            NSLayoutConstraint.activate([constraint])
            self.toastBottomConstraint = constraint
        } else {
            self.toastBottomConstraint = toastView.autoPinEdge(edge, to: edge, of: view, withOffset: offset)
        }

        if UIDevice.current.isIPad {
            // As wide as possible, not exceeding 512 pt, and not exceeding superview width
            toastView.autoHCenterInSuperview()
            toastView.autoSetDimension(.width, toSize: 512, relation: .lessThanOrEqual)/*.priority = .defaultLow*/
            toastView.autoPinWidthToSuperview(withMargin: 8, relation: .lessThanOrEqual)
            toastView.autoPinWidthToSuperview(withMargin: 8).forEach { $0.priority = .defaultHigh }
        } else {
            toastView.autoPinWidthToSuperview(withMargin: 8)
        }

        if let currentToastController = type(of: self).currentToastController {
            currentToastController.dismissToastView()
            type(of: self).currentToastController = nil
        }
        type(of: self).currentToastController = self

        UIView.animate(withDuration: 0.2) {
            toastView.alpha = 1
        }

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + dismissAfter) {
            // intentional strong reference to self.
            // As with an AlertController, the caller likely expects toast to
            // be presented and dismissed without maintaining a strong reference to ToastController
            self.dismissToastView()
        }
    }

    // MARK: - Keyboard

    private var toastBottomConstraint: NSLayoutConstraint?
    private var viewToPinTo: UIView?
    private var offset: CGFloat?

    private func keyboardConstraint(toastView: ToastView, viewOwningKeyboard: UIView) -> NSLayoutConstraint {
        return NSLayoutConstraint(
            item: toastView,
            attribute: .bottom,
            relatedBy: .equal,
            toItem: viewOwningKeyboard.keyboardLayoutGuide,
            attribute: .top,
            multiplier: 1.0,
            constant: -8
        )
    }

    @objc
    private func keyboardDidAppear() {
        keyboardPresenceDidChange(isPresent: true)
    }

    @objc
    private func keyboardDidHide() {
        keyboardPresenceDidChange(isPresent: false)
    }

    private func keyboardPresenceDidChange(isPresent: Bool) {
        if
            let constraint = self.toastBottomConstraint,
            let view = self.viewToPinTo,
            let offset = offset,
            let toastView = toastView
        {
            NSLayoutConstraint.deactivate([constraint])
            let newConstraint: NSLayoutConstraint
            if isPresent {
                newConstraint = keyboardConstraint(toastView: toastView, viewOwningKeyboard: view)
            } else {
                newConstraint = toastView.autoPinEdge(.bottom, to: .bottom, of: view, withOffset: offset)
            }
            NSLayoutConstraint.activate([newConstraint])
            self.toastBottomConstraint = newConstraint
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

        guard !isDismissing, let toastView = toastView else {
            return
        }
        isDismissing = true

        if type(of: self).currentToastController == self {
            type(of: self).currentToastController = nil
        }

        UIView.animate(withDuration: 0.2,
                       animations: {
            toastView.alpha = 0
        },
                       completion: { (_) in
            toastView.removeFromSuperview()
            self.toastView = nil
        })
    }
}

protocol ToastViewDelegate: AnyObject {
    func didTapToastView(_ toastView: ToastView)
    func didSwipeToastView(_ toastView: ToastView)
}

final class ToastView: UIView {

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

        let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        addSubview(blurEffectView)
        blurEffectView.autoPinEdgesToSuperviewEdges()

        addSubview(darkThemeBackgroundOverlay)
        darkThemeBackgroundOverlay.autoPinEdgesToSuperviewEdges()
        darkThemeBackgroundOverlay.backgroundColor = UIColor.white.withAlphaComponent(0.10)

        label.textColor = .ows_white
        label.font = UIFont.dynamicTypeSubheadline
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
    private func applyTheme() {
        darkThemeBackgroundOverlay.isHidden = !Theme.isDarkThemeEnabled
    }

    @objc
    private func didTap(gesture: UITapGestureRecognizer) {
        self.delegate?.didTapToastView(self)
    }

    @objc
    private func didSwipe(gesture: UISwipeGestureRecognizer) {
        self.delegate?.didSwipeToastView(self)
    }
}

// MARK: -

public extension UIView {
    func presentToast(text: String, fromViewController: UIViewController) {
        fromViewController.presentToast(text: text)
    }
}

// MARK: -

public extension UIViewController {
    func presentToast(text: String, extraVInset: CGFloat = 0) {
        let toastController = ToastController(text: text)
        // TODO: There should be a better way to do this.
        let bottomInset = view.safeAreaInsets.bottom + 8 + extraVInset
        toastController.presentToastView(from: .bottom, of: view, inset: bottomInset)
    }
}
