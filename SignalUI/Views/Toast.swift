//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import PureLayout
import SignalServiceKit

public class ToastController: NSObject, ToastViewDelegate {

    static var currentToastController: ToastController?

    private weak var toastView: ToastView?
    private var isDismissing: Bool
    private let toastText: String
    private let toastIcon: UIImage?

    // MARK: Initializers

    public init(text: String, image: UIImage? = nil) {
        self.toastText = text
        self.toastIcon = image
        isDismissing = false

        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidHide), name: UIResponder.keyboardDidHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidAppear), name: UIResponder.keyboardDidShowNotification, object: nil)
    }

    // MARK: Public

    public func presentToastView(
        from edge: ALEdge,
        of view: UIView,
        inset: CGFloat,
        dismissAfter: DispatchTimeInterval = .seconds(4),
    ) {
        let toastView = ToastView()
        toastView.text = self.toastText
        toastView.image = self.toastIcon
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

        // As wide as possible, not exceeding 512 pt, and not exceeding superview width
        toastView.autoSetDimension(.width, toSize: 512, relation: .lessThanOrEqual)
        toastView.centerXAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.centerXAnchor).isActive = true

        toastView.autoPinEdge(toSuperviewSafeArea: .leading, withInset: 8, relation: .greaterThanOrEqual)
        toastView.autoPinEdge(toSuperviewSafeArea: .trailing, withInset: 8, relation: .greaterThanOrEqual)
        toastView.autoPinEdge(toSuperviewSafeArea: .leading, withInset: 8).priority = .defaultHigh
        toastView.autoPinEdge(toSuperviewSafeArea: .trailing, withInset: 8).priority = .defaultHigh

        if let currentToastController = type(of: self).currentToastController {
            currentToastController.dismissToastView()
            type(of: self).currentToastController = nil
        }
        type(of: self).currentToastController = self

        toastView.animateIn()

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
            constant: -8,
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
            let offset,
            let toastView
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

        guard !isDismissing, let toastView else {
            return
        }
        isDismissing = true

        if type(of: self).currentToastController == self {
            type(of: self).currentToastController = nil
        }

        toastView.animateOut {
            toastView.removeFromSuperview()
            self.toastView = nil
        }
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

    var image: UIImage? {
        didSet {
            imageView.image = image
            imageView.isHiddenInStackView = (image == nil)
        }
    }

    weak var delegate: ToastViewDelegate?

    private let backgroundView = UIVisualEffectView(effect: nil)
    private let stackView: UIStackView
    private let label: UILabel
    private let imageView = UIImageView()

    @available(iOS 26.3, *)
    private var glassEffect: UIGlassEffect {
        let glassEffect = UIGlassEffect(style: .regular)
        glassEffect.tintColor = UIColor(
            light: UIColor(rgbHex: 0x3C3C43, alpha: 0.64),
            dark: UIColor(rgbHex: 0xEBEBF5, alpha: 0.24),
        )
        return glassEffect
    }

    // MARK: Initializers

    override init(frame: CGRect) {
        label = UILabel()
        stackView = UIStackView(arrangedSubviews: [label])
        super.init(frame: frame)

        // iOS 26.0 through 26.2 have a bug where the glass effect tint color
        // would not be present during animations. This was fixed in 26.3.
        if #available(iOS 26.3, *) {
            stackView.insertArrangedSubview(imageView, at: 0)
            imageView.autoSetDimensions(to: .square(24))

            backgroundView.effect = glassEffect
            backgroundView.contentView.layoutMargins = .init(hMargin: 20, vMargin: 14)
            backgroundView.cornerConfiguration = .capsule(maximumRadius: 26)

            label.font = .dynamicTypeBody
        } else {
            backgroundView.effect = UIBlurEffect(style: .dark)
            backgroundView.contentView.layoutMargins = .init(margin: 12)

            self.layer.cornerRadius = 12
            self.clipsToBounds = true

            label.font = UIFont.dynamicTypeSubheadline
        }
        addSubview(backgroundView)
        backgroundView.autoPinHeightToSuperview()
        backgroundView.autoPinWidthToSuperview(relation: .lessThanOrEqual)
        backgroundView.autoHCenterInSuperview()

        if #unavailable(iOS 26.3) {
            let darkThemeBackgroundOverlay = UIView()
            addSubview(darkThemeBackgroundOverlay)
            darkThemeBackgroundOverlay.autoPinEdgesToSuperviewEdges()
            darkThemeBackgroundOverlay.backgroundColor = UIColor(
                light: .clear,
                dark: UIColor.white.withAlphaComponent(0.10),
            )
        }

        imageView.tintColor = .white

        label.textColor = .ows_white
        label.numberOfLines = 0

        stackView.axis = .horizontal
        stackView.spacing = 12
        stackView.alignment = .center
        backgroundView.contentView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap(gesture:)))
        self.addGestureRecognizer(tapGesture)

        let swipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(didSwipe(gesture:)))
        self.addGestureRecognizer(swipeGesture)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Gestures

    @objc
    private func didTap(gesture: UITapGestureRecognizer) {
        self.delegate?.didTapToastView(self)
    }

    @objc
    private func didSwipe(gesture: UISwipeGestureRecognizer) {
        self.delegate?.didSwipeToastView(self)
    }

    // MARK: Animations

    fileprivate func animateIn() {
        let animator = UIViewPropertyAnimator(duration: 0.35, springDamping: 1, springResponse: 0.35)

        if #available(iOS 26.3, *) {
            UIView.performWithoutAnimation {
                self.stackView.alpha = 0
                self.transform = .scale(0.9)
                self.backgroundView.effect = nil
            }

            animator.addAnimations {
                self.stackView.alpha = 1
                self.transform = .identity
                self.backgroundView.effect = self.glassEffect
            }
        } else {
            self.alpha = 0
            animator.addAnimations {
                self.alpha = 1
            }
        }

        animator.startAnimation()
    }

    fileprivate func animateOut(completion: @escaping () -> Void) {
        let animator = UIViewPropertyAnimator(duration: 0.35, springDamping: 1, springResponse: 0.35)
        animator.addCompletion { _ in
            completion()
        }

        if #available(iOS 26.3, *) {
            animator.addAnimations {
                self.stackView.alpha = 0
                self.transform = .scale(0.9)
                self.backgroundView.effect = nil
            }
        } else {
            animator.addAnimations {
                self.alpha = 0
            }
        }
        animator.startAnimation()
    }
}

public class ToastViewHelper {
    public static func presentToastOnFrontmostViewController(text: String, image: UIImage? = nil) {
        guard let fromViewController = CurrentAppContext().frontmostViewController() else {
            owsFailDebug("frontmostViewController was unexpectedly nil")
            return
        }
        fromViewController.presentToast(text: text, image: image)
    }
}

// MARK: -

public extension UIView {
    func presentToast(text: String, image: UIImage? = nil, fromViewController: UIViewController) {
        fromViewController.presentToast(text: text, image: image)
    }
}

// MARK: -

public extension UIViewController {
    func presentToast(text: String, image: UIImage? = nil, extraVInset: CGFloat = 0) {
        let toastController = ToastController(text: text, image: image)
        // TODO: There should be a better way to do this.
        let bottomInset = view.safeAreaInsets.bottom + 8 + extraVInset
        toastController.presentToastView(from: .bottom, of: view, inset: bottomInset)
    }
}
