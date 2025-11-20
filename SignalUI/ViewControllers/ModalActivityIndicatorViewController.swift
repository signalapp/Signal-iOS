//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import MediaPlayer
public import SignalServiceKit

// A modal view that be used during blocking interactions (e.g. waiting on response from
// service or on the completion of a long-running local operation).
public class ModalActivityIndicatorViewController: OWSViewController {
    public enum Constants {
        public static let defaultPresentationDelay: TimeInterval = 0.05
    }

    private(set) public var wasCancelled: Bool = false

    private let canCancel: Bool
    private let isInvisible: Bool
    private var wasDimissed: Bool = false
    private var activityIndicator: UIActivityIndicatorView?
    private var presentTimer: Timer?
    private let presentationDelay: TimeInterval
    private var asyncTask: Task<Void, Never>?

    public init(canCancel: Bool, presentationDelay: TimeInterval, isInvisible: Bool = false) {
        self.canCancel = canCancel
        self.presentationDelay = presentationDelay
        self.isInvisible = isInvisible
        super.init()
    }

    // MARK: -

    @MainActor
    public class func present(
        fromViewController: UIViewController,
        canCancel: Bool,
        presentationDelay: TimeInterval = Constants.defaultPresentationDelay,
        backgroundBlockQueueQos: DispatchQoS = .default,
        backgroundBlock: @escaping (ModalActivityIndicatorViewController) -> Void
    ) {
        present(
            fromViewController: fromViewController,
            canCancel: canCancel,
            presentationDelay: presentationDelay,
            isInvisible: false,
            backgroundBlockQueueQos: backgroundBlockQueueQos,
            backgroundBlock: backgroundBlock
        )
    }

    @MainActor
    public class func presentAsInvisible(
        fromViewController: UIViewController,
        backgroundBlock: @escaping (ModalActivityIndicatorViewController) -> Void
    ) {
        present(
            fromViewController: fromViewController,
            canCancel: false,
            presentationDelay: Constants.defaultPresentationDelay,
            isInvisible: true,
            backgroundBlockQueueQos: .default,
            backgroundBlock: backgroundBlock
        )
    }

    @MainActor
    private class func present(
        fromViewController: UIViewController,
        canCancel: Bool,
        presentationDelay: TimeInterval,
        isInvisible: Bool,
        backgroundBlockQueueQos: DispatchQoS,
        backgroundBlock: @escaping (ModalActivityIndicatorViewController) -> Void
    ) {
        AssertIsOnMainThread()

        ModalActivityIndicatorViewController(
            canCancel: canCancel,
            presentationDelay: presentationDelay,
            isInvisible: isInvisible
        ).present(
            from: fromViewController,
            asyncBlock: { viewController in
                DispatchQueue.global(qos: backgroundBlockQueueQos.qosClass).async {
                    backgroundBlock(viewController)
                }
            }
        )
    }

    // MARK: -

    /// Presents a `ModalActivityIndicatorViewController`, behind which the
    /// given async block runs. Callers are expected to dismiss the modal at the
    /// completion of the async block.
    ///
    /// Use this API if you need fine-grained control over the modal dismissal
    /// behavior, or if you want a cancellable modal.
    ///
    /// - SeeAlso ``presentAndPropagateResult(from:presentationDelay:wrappedAsyncBlock:)``
    @MainActor
    public class func present(
        fromViewController: UIViewController,
        canCancel: Bool = false,
        presentationDelay: TimeInterval = Constants.defaultPresentationDelay,
        isInvisible: Bool = false,
        asyncBlock: @escaping @MainActor (ModalActivityIndicatorViewController) async -> Void
    ) {
        AssertIsOnMainThread()

        ModalActivityIndicatorViewController(
            canCancel: canCancel,
            presentationDelay: presentationDelay,
            isInvisible: isInvisible
        ).present(
            from: fromViewController,
            asyncBlock: asyncBlock
        )
    }

    /// Presents a `ModalActivityIndicatorViewController` for the duration of
    /// the given async block, automatically dismissing the modal when the block
    /// exits and propagating the block's result.
    ///
    /// Use this API if you want to simply show a modal during a non-cancellable
    /// async block.
    ///
    /// - SeeAlso ``present(fromViewController:canCancel:presentationDelay:isInvisible:asyncBlock:)``.
    @MainActor
    public class func presentAndPropagateResult<T, E>(
        from viewController: UIViewController,
        canCancel: Bool = false,
        presentationDelay: TimeInterval = Constants.defaultPresentationDelay,
        wrappedAsyncBlock: @escaping () async throws(E) -> T
    ) async throws(E) -> T {
        let result: Result<T, E> = await withCheckedContinuation { continuation in
            present(
                fromViewController: viewController,
                canCancel: canCancel,
                presentationDelay: presentationDelay,
                asyncBlock: { modal in
                    let result = await Result(catching: wrappedAsyncBlock)
                    modal.dismiss {
                        continuation.resume(returning: result)
                    }
                }
            )
        }

        return try result.get()
    }

    @MainActor
    private func present(from viewController: UIViewController, asyncBlock: @escaping @MainActor (ModalActivityIndicatorViewController) async -> Void) {
        // Present this modal _over_ the current view contents.
        self.modalPresentationStyle = .overFullScreen
        viewController.present(self, animated: false) {
            self.asyncTask = Task { await asyncBlock(self) }
            if self.wasCancelled {
                self.asyncTask?.cancel()
            }
        }
    }

    // MARK: -

    public func dismiss(completion: (() -> Void)? = nil) {
        AssertIsOnMainThread()

        if !wasDimissed {
            // Only dismiss once.
            self.dismiss(animated: false, completion: completion)
            wasDimissed = true
        } else {
            // If already dismissed, wait a beat then call completion.
            DispatchQueue.main.async {
                completion?()
            }
        }
    }

    /// A helper for a common dismissal pattern.
    ///
    /// This can be invoked on any queue, and it'll switch to the main queue if
    /// needed. The completion block will be invoked on the main queue.
    ///
    /// - Parameter completionIfNotCanceled:
    ///     If the modal hasn't been canceled, dismiss it and then call this
    ///     block. Note: If the modal was canceled, the block isn't invoked.
    public func dismissIfNotCanceled(completionIfNotCanceled: @escaping () -> Void = {}) {
        DispatchQueue.main.async {
            if self.wasCancelled {
                return
            }
            self.dismiss(completion: completionIfNotCanceled)
        }
    }

    // MARK: -

    public override func loadView() {
        super.loadView()

        if isInvisible {
            self.view.backgroundColor = .clear
            self.view.isOpaque = false
        } else {
            self.view.backgroundColor = (Theme.isDarkThemeEnabled
                                            ? UIColor(white: 0.35, alpha: 0.35)
                                            : UIColor(white: 0, alpha: 0.25))
            self.view.isOpaque = false

            let activityIndicator = UIActivityIndicatorView(style: .large)
            self.activityIndicator = activityIndicator
            self.view.addSubview(activityIndicator)
            activityIndicator.autoCenterInSuperview()

            if canCancel {
                let cancelButton = UIButton(type: .custom)
                cancelButton.setTitle(CommonStrings.cancelButton, for: .normal)
                cancelButton.setTitleColor(UIColor.white, for: .normal)
                cancelButton.backgroundColor = UIColor.ows_gray80
                let font = UIFont.dynamicTypeHeadline
                cancelButton.titleLabel?.font = font
                cancelButton.layer.cornerRadius = .scaleFromIPhone5To7Plus(4, 5)
                cancelButton.clipsToBounds = true
                cancelButton.addTarget(self, action: #selector(cancelPressed), for: .touchUpInside)
                let buttonWidth = CGFloat.scaleFromIPhone5To7Plus(140, 160)
                let buttonHeight = OWSFlatButton.heightForFont(font)
                self.view.addSubview(cancelButton)
                cancelButton.autoHCenterInSuperview()
                cancelButton.autoPinEdge(toSuperviewEdge: .bottom, withInset: 50)
                cancelButton.autoSetDimension(.width, toSize: buttonWidth)
                cancelButton.autoSetDimension(.height, toSize: buttonHeight)
            }
        }

        guard presentationDelay > 0 else {
            return
        }

        // Hide the modal until the presentation animation completes.
        self.view.layer.opacity = 0.0
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        self.activityIndicator?.startAnimating()

        guard presentationDelay > 0 else {
            return
        }

        // Hide the modal and wait for a second before revealing it,
        // to avoid "blipping" in the modal during short blocking operations.
        //
        // NOTE: It will still intercept user interactions while hidden, as it
        //       should.
        self.presentTimer?.invalidate()
        self.presentTimer = Timer.scheduledTimer(withTimeInterval: presentationDelay, repeats: false) { [weak self] _ in
            self?.presentTimerFired()
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        clearTimer()
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        self.activityIndicator?.stopAnimating()

        clearTimer()
    }

    // MARK: -

    private func clearTimer() {
        self.presentTimer?.invalidate()
        self.presentTimer = nil
    }

    private func presentTimerFired() {
        AssertIsOnMainThread()

        clearTimer()

        // Fade in the modal.
        UIView.animate(withDuration: 0.35) {
            self.view.layer.opacity = 1.0
        }
    }

    @objc
    private func cancelPressed() {
        AssertIsOnMainThread()

        if self.wasDimissed {
            return
        }

        self.dismiss()
        self.wasCancelled = true
        self.asyncTask?.cancel()
    }
}
