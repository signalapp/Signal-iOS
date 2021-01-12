//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSSheetViewControllerDelegate)
public protocol SheetViewControllerDelegate: class {
    func sheetViewControllerRequestedDismiss(_ sheetViewController: SheetViewController)
}

@objc(OWSSheetViewController)
public class SheetViewController: UIViewController {

    @objc
    weak var delegate: SheetViewControllerDelegate?

    @objc
    public let contentView: UIView = UIView()

    private let sheetView: SheetView = SheetView()
    private let handleView: UIView = UIView()

    deinit {
        Logger.verbose("")
    }

    @objc
    public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        self.transitioningDelegate = self
        self.modalPresentationStyle = .overCurrentContext
    }

    public required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    // MARK: View LifeCycle

    var sheetViewVerticalConstraint: NSLayoutConstraint?

    override public func loadView() {
        self.view = UIView()

        sheetView.preservesSuperviewLayoutMargins = true

        sheetView.addSubview(contentView)
        contentView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        contentView.autoPinEdge(toSuperviewMargin: .bottom)

        view.addSubview(sheetView)
        sheetView.autoPinWidthToSuperview()
        sheetView.setContentHuggingVerticalHigh()
        sheetView.setCompressionResistanceHigh()
        self.sheetViewVerticalConstraint = sheetView.autoPinEdge(.top, to: .bottom, of: self.view)

        handleView.backgroundColor = Theme.isDarkThemeEnabled ? UIColor.ows_white : UIColor.ows_gray05
        let kHandleViewHeight: CGFloat = 5
        handleView.autoSetDimensions(to: CGSize(width: 40, height: kHandleViewHeight))
        handleView.layer.cornerRadius = kHandleViewHeight / 2
        view.addSubview(handleView)
        handleView.autoAlignAxis(.vertical, toSameAxisOf: sheetView)
        handleView.autoPinEdge(.bottom, to: .top, of: sheetView, withOffset: -6)

        // Gestures
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTapBackground))
        self.view.addGestureRecognizer(tapGesture)

        let swipeDownGesture = UISwipeGestureRecognizer(target: self, action: #selector(didSwipeDown))
        swipeDownGesture.direction = .down
        self.view.addGestureRecognizer(swipeDownGesture)
    }

    // MARK: Present / Dismiss animations

    fileprivate func animatePresentation(completion: @escaping (Bool) -> Void) {
        guard let sheetViewVerticalConstraint = self.sheetViewVerticalConstraint else {
            owsFailDebug("sheetViewVerticalConstraint was unexpectedly nil")
            return
        }

        let backgroundDuration: TimeInterval = 0.1
        UIView.animate(withDuration: backgroundDuration) {
            let alpha: CGFloat = Theme.isDarkThemeEnabled ? 0.7 : 0.6
            self.view.backgroundColor = UIColor.black.withAlphaComponent(alpha)
        }

        self.sheetView.superview?.layoutIfNeeded()

        NSLayoutConstraint.deactivate([sheetViewVerticalConstraint])
        self.sheetViewVerticalConstraint = self.sheetView.autoPinEdge(toSuperviewEdge: .bottom)
        UIView.animate(withDuration: 0.2,
                       delay: backgroundDuration,
                       options: .curveEaseOut,
                       animations: {
                        self.sheetView.superview?.layoutIfNeeded()
        },
                       completion: completion)
    }

    fileprivate func animateDismiss(completion: @escaping (Bool) -> Void) {
        guard let sheetViewVerticalConstraint = self.sheetViewVerticalConstraint else {
            owsFailDebug("sheetVerticalConstraint was unexpectedly nil")
            return
        }

        self.sheetView.superview?.layoutIfNeeded()
        NSLayoutConstraint.deactivate([sheetViewVerticalConstraint])

        let dismissDuration: TimeInterval = 0.2
        self.sheetViewVerticalConstraint = self.sheetView.autoPinEdge(.top, to: .bottom, of: self.view)
        UIView.animate(withDuration: dismissDuration,
                       delay: 0,
                       options: .curveEaseOut,
                       animations: {
                        self.view.backgroundColor = UIColor.clear
                        self.sheetView.superview?.layoutIfNeeded()
        },
                       completion: completion)
    }

    // MARK: Actions

    @objc
    func didTapBackground() {
        // inform delegate to
        delegate?.sheetViewControllerRequestedDismiss(self)
    }

    @objc
    func didSwipeDown() {
        // inform delegate to
        delegate?.sheetViewControllerRequestedDismiss(self)
    }
}

extension SheetViewController: UIViewControllerTransitioningDelegate {
    public func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return SheetViewPresentationController(sheetViewController: self)
    }

    public func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return SheetViewDismissalController(sheetViewController: self)
    }
}

private class SheetViewPresentationController: NSObject, UIViewControllerAnimatedTransitioning {

    let sheetViewController: SheetViewController
    init(sheetViewController: SheetViewController) {
        self.sheetViewController = sheetViewController
    }

    // This is used for percent driven interactive transitions, as well as for
    // container controllers that have companion animations that might need to
    // synchronize with the main animation.
    public func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.3
    }

    // This method can only be a nop if the transition is interactive and not a percentDriven interactive transition.
    public func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        Logger.debug("")
        transitionContext.containerView.addSubview(sheetViewController.view)
        sheetViewController.view.autoPinEdgesToSuperviewEdges()
        sheetViewController.animatePresentation { didComplete in
            Logger.debug("completed: \(didComplete)")
            transitionContext.completeTransition(didComplete)
        }
    }
}

private class SheetViewDismissalController: NSObject, UIViewControllerAnimatedTransitioning {

    let sheetViewController: SheetViewController
    init(sheetViewController: SheetViewController) {
        self.sheetViewController = sheetViewController
    }

    // This is used for percent driven interactive transitions, as well as for
    // container controllers that have companion animations that might need to
    // synchronize with the main animation.
    public func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.3
    }

    // This method can only be a nop if the transition is interactive and not a percentDriven interactive transition.
    public func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        Logger.debug("")
        sheetViewController.animateDismiss { didComplete in
            Logger.debug("completed: \(didComplete)")
            transitionContext.completeTransition(didComplete)
        }
    }
}

private class SheetView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = Theme.isDarkThemeEnabled ? UIColor.ows_gray90
            : UIColor.ows_gray05
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    override var bounds: CGRect {
        didSet {
            updateMask()
        }
    }

    private func updateMask() {
        let cornerRadius: CGFloat = 16
        let path: UIBezierPath = UIBezierPath(roundedRect: bounds, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: cornerRadius, height: cornerRadius))
        let mask = CAShapeLayer()
        mask.path = path.cgPath
        self.layer.mask = mask
    }
}
