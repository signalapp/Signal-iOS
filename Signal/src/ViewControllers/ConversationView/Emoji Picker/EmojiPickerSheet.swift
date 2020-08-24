//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
class EmojiPickerSheet: UIViewController {
    let contentView = UIView()
    let handle = UIView()
    weak var backdropView: UIView?

    let completionHandler: (EmojiWithSkinTones?) -> Void

    let collectionView = EmojiPickerCollectionView()
    lazy var sectionToolbar = EmojiPickerSectionToolbar(delegate: self)

    init(completionHandler: @escaping (EmojiWithSkinTones?) -> Void) {
        self.completionHandler = completionHandler
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        transitioningDelegate = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: -

    override public func loadView() {
        view = UIView()
        view.backgroundColor = .clear

        view.addSubview(contentView)
        contentView.autoPinEdge(toSuperviewEdge: .bottom)
        contentView.autoHCenterInSuperview()
        contentView.autoMatch(.height, to: .height, of: view, withOffset: 0, relation: .lessThanOrEqual)
        contentView.backgroundColor = Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_white

        // Prefer to be full width, but don't exceed the maximum width
        contentView.autoSetDimension(.width, toSize: maxWidth, relation: .lessThanOrEqual)
        NSLayoutConstraint.autoSetPriority(.defaultHigh) {
            contentView.autoPinWidthToSuperview()
        }

        contentView.addSubview(collectionView)
        collectionView.autoPinEdgesToSuperviewEdges()
        collectionView.pickerDelegate = self

        // Support tapping the backdrop to cancel the action sheet.
        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(didTapBackdrop(_:)))
        tapGestureRecognizer.delegate = self
        view.addGestureRecognizer(tapGestureRecognizer)

        // Setup handle for interactive dismissal / resizing
        setupInteractiveSizing()

        contentView.addSubview(sectionToolbar)
        sectionToolbar.autoPinWidthToSuperview()
        sectionToolbar.autoPinEdge(toSuperviewEdge: .bottom)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { _ in
            self.collectionView.reloadData()
        }, completion: nil)
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Ensure the scrollView's layout has completed
        // as we're about to use its bounds to calculate
        // the masking view and contentOffset.
        contentView.layoutIfNeeded()

        // Ensure you can scroll to the last emoji without
        // them being stuck behind the toolbar.
        collectionView.contentInset = UIEdgeInsets(top: 0, leading: 0, bottom: sectionToolbar.height, trailing: 0)

        let cornerRadius: CGFloat = 16
        let path = UIBezierPath(
            roundedRect: contentView.bounds,
            byRoundingCorners: [.topLeft, .topRight],
            cornerRadii: CGSize(square: cornerRadius)
        )
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        contentView.layer.mask = shapeLayer
    }

    @objc func didTapBackdrop(_ sender: UITapGestureRecognizer) {
        completionHandler(nil)
        dismiss(animated: true)
    }

    // MARK: - Resize / Interactive Dismiss

    var heightConstraint: NSLayoutConstraint?
    let maxWidth: CGFloat = 512
    var minimizedHeight: CGFloat {
        return min(maximizedHeight, 346)
    }
    var maximizedHeight: CGFloat {
        return CurrentAppContext().frame.height - topLayoutGuide.length - 32
    }

    let maxAnimationDuration: TimeInterval = 0.2
    var startingHeight: CGFloat?
    var startingTranslation: CGFloat?

    func setupInteractiveSizing() {
        heightConstraint = contentView.autoSetDimension(.height, toSize: minimizedHeight)

        // Create a pan gesture to handle when the user interacts with the
        // view outside of the collection view.
        let panGestureRecognizer = DirectionalPanGestureRecognizer(direction: .vertical, target: self, action: #selector(handlePan))
        view.addGestureRecognizer(panGestureRecognizer)
        panGestureRecognizer.delegate = self

        // We also want to handle the pan gesture for the collection view,
        // so we can do a nice scroll to dismiss gesture, and so we can
        // transfer any initial scrolling into maximizing the view.
        collectionView.panGestureRecognizer.addTarget(self, action: #selector(handlePan))

        handle.backgroundColor = .ows_whiteAlpha80
        handle.autoSetDimensions(to: CGSize(width: 56, height: 5))
        handle.layer.cornerRadius = 5 / 2
        view.addSubview(handle)
        handle.autoHCenterInSuperview()
        handle.autoPinEdge(.bottom, to: .top, of: contentView, withOffset: -8)
    }

    @objc func handlePan(_ sender: UIPanGestureRecognizer) {
        let isCollectionViewPanGesture = sender == collectionView.panGestureRecognizer

        switch sender.state {
        case .began, .changed:
            guard beginInteractiveTransitionIfNecessary(sender),
                let startingHeight = startingHeight,
                let startingTranslation = startingTranslation else {
                    return resetInteractiveTransition()
            }

            // We're in an interactive transition, so don't let the scrollView scroll.
            if isCollectionViewPanGesture {
                collectionView.contentOffset.y = 0
                collectionView.showsVerticalScrollIndicator = false
            }

            // We may have panned some distance if we were scrolling before we started
            // this interactive transition. Offset the translation we use to move the
            // view by whatever the translation was when we started the interactive
            // portion of the gesture.
            let translation = sender.translation(in: view).y - startingTranslation

            var newHeight = startingHeight - translation
            if newHeight > maximizedHeight {
                newHeight = maximizedHeight
            }

            // If the height is decreasing, adjust the relevant view's proporitionally
            if newHeight < startingHeight {
                backdropView?.alpha = 1 - (startingHeight - newHeight) / startingHeight
            }

            // Update our height to reflect the new position
            heightConstraint?.constant = newHeight
            view.layoutIfNeeded()
        case .ended, .cancelled, .failed:
            guard let startingHeight = startingHeight else { break }

            let dismissThreshold = startingHeight * 0.5
            let growThreshold = startingHeight * 1.5
            let velocityThreshold: CGFloat = 500

            let currentHeight = contentView.height
            let currentVelocity = sender.velocity(in: view).y

            enum CompletionState { case growing, dismissing, cancelling }
            let completionState: CompletionState

            if abs(currentVelocity) >= velocityThreshold {
                completionState = currentVelocity < 0 ? .growing : .dismissing
            } else if currentHeight >= growThreshold {
                completionState = .growing
            } else if currentHeight <= dismissThreshold {
                completionState = .dismissing
            } else {
                completionState = .cancelling
            }

            let finalHeight: CGFloat
            switch completionState {
            case .dismissing:
                finalHeight = 0
            case .growing:
                finalHeight = maximizedHeight
            case .cancelling:
                finalHeight = startingHeight

                if isCollectionViewPanGesture {
                    collectionView.setContentOffset(collectionView.contentOffset, animated: false)
                }
            }

            let remainingDistance = finalHeight - currentHeight

            // Calculate the time to complete the animation if we want to preserve
            // the user's velocity. If this time is too slow (e.g. the user was scrolling
            // very slowly) we'll default to `maxAnimationDuration`
            let remainingTime = TimeInterval(abs(remainingDistance / currentVelocity))

            UIView.animate(withDuration: min(remainingTime, maxAnimationDuration), delay: 0, options: .curveEaseOut, animations: {
                if remainingDistance < 0 {
                    self.contentView.frame.origin.y -= remainingDistance
                    self.handle.frame.origin.y -= remainingDistance
                } else {
                    self.heightConstraint?.constant = finalHeight
                    self.view.layoutIfNeeded()
                }

                self.backdropView?.alpha = completionState == .dismissing ? 0 : 1
            }) { _ in
                self.heightConstraint?.constant = finalHeight
                self.view.layoutIfNeeded()

                if completionState == .dismissing {
                    self.completionHandler(nil)
                    self.dismiss(animated: true)
                }
            }

            resetInteractiveTransition()
        default:
            resetInteractiveTransition()

            backdropView?.alpha = 1

            guard let startingHeight = startingHeight else { break }
            heightConstraint?.constant = startingHeight
        }
    }

    func beginInteractiveTransitionIfNecessary(_ sender: UIPanGestureRecognizer) -> Bool {
        // If we're at the top of the scrollView, the the view is not
        // currently maximized, or we're panning outside of the collection
        // view we want to do an interactive transition.
        guard collectionView.contentOffset.y <= 0
            || contentView.height < maximizedHeight
            || sender != collectionView.panGestureRecognizer else { return false }

        if startingTranslation == nil {
            startingTranslation = sender.translation(in: view).y
        }

        if startingHeight == nil {
            startingHeight = contentView.height
        }

        return true
    }

    func resetInteractiveTransition() {
        startingTranslation = nil
        startingHeight = nil
        collectionView.showsVerticalScrollIndicator = true
    }
}

extension EmojiPickerSheet: EmojiPickerSectionToolbarDelegate {
    func emojiPickerSectionToolbar(_ sectionToolbar: EmojiPickerSectionToolbar, didSelectSection section: Int) {
        collectionView.scrollToSectionHeader(section, animated: false)

        guard heightConstraint?.constant != maximizedHeight else { return }

        UIView.animate(withDuration: maxAnimationDuration, delay: 0, options: .curveEaseOut, animations: {
            self.heightConstraint?.constant = self.maximizedHeight
            self.view.layoutIfNeeded()
            self.backdropView?.alpha = 1
        })
    }

    func emojiPickerSectionToolbarShouldShowRecentsSection(_ sectionToolbar: EmojiPickerSectionToolbar) -> Bool {
        return collectionView.hasRecentEmoji
    }
}

extension EmojiPickerSheet: EmojiPickerCollectionViewDelegate {
    func emojiPicker(_ emojiPicker: EmojiPickerCollectionView, didSelectEmoji emoji: EmojiWithSkinTones) {
        completionHandler(emoji)
        dismiss(animated: true)
    }

    func emojiPicker(_ emojiPicker: EmojiPickerCollectionView, didScrollToSection section: Int) {
        sectionToolbar.setSelectedSection(section)
    }
}

// MARK: -
extension EmojiPickerSheet: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        switch gestureRecognizer {
        case is UITapGestureRecognizer:
            let point = gestureRecognizer.location(in: view)
            guard !contentView.frame.contains(point) else { return false }
            return true
        default:
            return true
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        switch gestureRecognizer {
        case is UIPanGestureRecognizer:
            return collectionView.panGestureRecognizer == otherGestureRecognizer
        default:
            return false
        }
    }
}

// MARK: -

private class EmojiPickerAnimationController: UIPresentationController {

    var backdropView: UIView? {
        guard let vc = presentedViewController as? EmojiPickerSheet else { return nil }
        return vc.backdropView
    }

    override func presentationTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdropView?.alpha = 1
        }, completion: nil)
    }

    override func dismissalTransitionWillBegin() {
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.backdropView?.alpha = 0
        }, completion: nil)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        guard let presentedView = presentedView else { return }
        coordinator.animate(alongsideTransition: { _ in
            presentedView.frame = self.frameOfPresentedViewInContainerView
            presentedView.layoutIfNeeded()
        }, completion: nil)
    }
}

extension EmojiPickerSheet: UIViewControllerTransitioningDelegate {
    public func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        return EmojiPickerAnimationController(presentedViewController: presented, presenting: presenting)
    }
}
