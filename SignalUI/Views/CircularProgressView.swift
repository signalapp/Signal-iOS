//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
public import UIKit

public class CircularProgressView: UIView {

    // MARK: - Progress

    private var _progress: Float = 0

    private enum IndeternimateAnimationState: Equatable {
        /// Not in "indeternimate animation" state.
        case notAnimating
        /// Speeding up.
        case phase1(CFTimeInterval)
        /// Infinite spin..
        case phase2
        /// Transitioning to determinate progress.
        case phase3
    }

    private enum Animation {
        enum Indeternimate {
            // How long does it take for the spinner stroke to grow and do initial rotation.
            static let phaseOneDuration: CFTimeInterval = 1
            // How long does it take for the spinner to do once full rotation.
            static let phaseTwoDuration: CFTimeInterval = 1

            static let strokeGrow = "indeterminate.strokeGrow"
            static let strokeSpin = "indeterminate.strokeSpin"
            static let infiniteSpin = "indeterminate.infiniteSpin"
        }

        enum Determinate {
            static let duration: CFTimeInterval = 0.2

            static let strokeResize = "determinate.strokeResize"
        }
    }

    public var progress: Float {
        get { _progress }
        set { setProgress(newValue, animated: false) }
    }

    public func setProgress(_ newValue: Float, animated: Bool) {
        // Can switch to determinate if indeterminate is starting or running.
        if isAnimating {
            switchToDeterminate(progress: newValue, animated: animated)
            return
        }

        _progress = newValue.clamp01()

        // If state is `phase3` we want to preserve the progress but not interfere with the animation.
        // Instead, once animation finishes, the view will update to match current `progress`.
        guard case .notAnimating = animationState else {
            return
        }

        let progress = CGFloat(progress)

        if animated {
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = progressLayer.presentation()?.strokeEnd ?? progressLayer.strokeEnd
            animation.toValue = progress
            animation.duration = Animation.Determinate.duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            progressLayer.add(animation, forKey: Animation.Determinate.strokeResize)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true) // suppress implicit animation
        progressLayer.strokeEnd = progress
        CATransaction.commit()
    }

    private var animationState: IndeternimateAnimationState = .notAnimating

    public var isAnimating: Bool {
        switch animationState {
        case .notAnimating:
            false
        case .phase1(_), .phase2:
            true
        case .phase3:
            false
        }
    }

    public func startAnimating() {
        guard animationState == .notAnimating else { return }

        _progress = 0

        // Reset to default state.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = 0
        progressLayer.transform = CATransform3DIdentity
        CATransaction.commit()

        // Phase 1 animations.
        let strokeGrow = CABasicAnimation(keyPath: "strokeEnd")
        strokeGrow.fromValue = 0
        strokeGrow.toValue = 0.5
        strokeGrow.duration = Animation.Indeternimate.phaseOneDuration
        strokeGrow.timingFunction = CAMediaTimingFunction(name: .easeIn)
        strokeGrow.fillMode = .forwards
        strokeGrow.isRemovedOnCompletion = false

        let initialSpin = CABasicAnimation(keyPath: "transform.rotation.z")
        initialSpin.fromValue = 0
        initialSpin.toValue = 3 * CGFloat.halfPi
        initialSpin.duration = Animation.Indeternimate.phaseOneDuration
        initialSpin.timingFunction = CAMediaTimingFunction(name: .easeIn)
        initialSpin.fillMode = .forwards
        initialSpin.isRemovedOnCompletion = false

        let animationStartTime = CACurrentMediaTime()
        animationState = .phase1(animationStartTime)

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            // Make sure `startIndeterminate()` wasn't called in between.
            guard animationState == .phase1(animationStartTime) else { return }
            self.beginInfiniteSpin()
        }
        progressLayer.add(strokeGrow, forKey: Animation.Indeternimate.strokeGrow)
        progressLayer.add(initialSpin, forKey: Animation.Indeternimate.strokeSpin)
        CATransaction.commit()
    }

    private func beginInfiniteSpin() {
        // Necessary in case animation was interrupted during phase 1.
        guard case .phase1 = animationState else { return }

        // Bake state at end of phase 1 into the model layer before removing animations.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = 0.5
        progressLayer.transform = CATransform3DMakeRotation(3 * .halfPi, 0, 0, 1)
        CATransaction.commit()

        progressLayer.removeAnimation(forKey: Animation.Indeternimate.strokeGrow)
        progressLayer.removeAnimation(forKey: Animation.Indeternimate.strokeSpin)

        animationState = .phase2

        // Phase 2 animation: one full circle spin, repeaded indefinitely.
        let infiniteSpin = CABasicAnimation(keyPath: "transform.rotation.z")
        infiniteSpin.byValue = 2 * CGFloat.pi
        infiniteSpin.duration = Animation.Indeternimate.phaseTwoDuration
        infiniteSpin.repeatCount = .infinity
        infiniteSpin.timingFunction = CAMediaTimingFunction(name: .linear)
        progressLayer.add(infiniteSpin, forKey: Animation.Indeternimate.infiniteSpin)
    }

    public func stopAnimating() {
        guard isAnimating else { return }

        _progress = 0
        animationState = .notAnimating

        progressLayer.removeAnimation(forKey: Animation.Indeternimate.strokeGrow)
        progressLayer.removeAnimation(forKey: Animation.Indeternimate.strokeSpin)
        progressLayer.removeAnimation(forKey: Animation.Indeternimate.infiniteSpin)

        progressLayer.strokeEnd = 0
        progressLayer.transform = CATransform3DIdentity
    }

    private func switchToDeterminate(progress: Float, animated: Bool) {
        guard isAnimating else { return }

        let targetProgress = CGFloat(progress).clamp01()

        // 1. Snapshot current rotation.
        let currentRotation = progressLayer.presentation()?.value(forKeyPath: "transform.rotation.z") as? CGFloat ?? 0
        // Bring current rotation angle into 0..2pi range.
        // `visibleRotation` represents visible amount of rotation that the arc has relative to it's `default` state.
        // `visibleRotation` being zero corresponds to beginning of the arc being at 12 o'clock
        // and the end of the arc being at 6 o'clock.
        let doublePi = 2 * CGFloat.pi
        let visibleRotation =
            currentRotation.truncatingRemainder(dividingBy: doublePi) + (currentRotation < 0 ? doublePi : 0)

        // 2. Remove ALL of the animations, in case switch to deternimate happens before
        // spinner starts its infinite spin.
        progressLayer.removeAnimation(forKey: Animation.Indeternimate.strokeGrow)
        progressLayer.removeAnimation(forKey: Animation.Indeternimate.strokeSpin)
        progressLayer.removeAnimation(forKey: Animation.Indeternimate.infiniteSpin)

        // Simply update model and state if changes should not be animated.
        guard animated else {
            animationState = .notAnimating

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            progressLayer.strokeEnd = targetProgress
            progressLayer.transform = CATransform3DIdentity
            CATransaction.commit()

            return
        }

        // 3. Prepare layer to be animated to it's final state by applying current rotation angle.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = 0.5
        progressLayer.transform = CATransform3DMakeRotation(visibleRotation, 0, 0, 1)
        CATransaction.commit()

        // 4. Animate rotation back to 0 and strokeEnd to target progress simultaneously.
        let strokeLength = CABasicAnimation(keyPath: "strokeEnd")
        strokeLength.fromValue = 0.5
        strokeLength.toValue = targetProgress
        strokeLength.duration = Animation.Determinate.duration
        strokeLength.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let finalSpin = CABasicAnimation(keyPath: "transform.rotation.z")
        finalSpin.fromValue = visibleRotation
        finalSpin.toValue = 0
        finalSpin.duration = Animation.Determinate.duration
        finalSpin.timingFunction = CAMediaTimingFunction(name: .easeOut)

        animationState = .phase3

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self else { return }
            guard self.animationState == .phase3 else { return }

            self.animationState = .notAnimating

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.progressLayer.strokeEnd = targetProgress
            self.progressLayer.transform = CATransform3DIdentity
            CATransaction.commit()
        }
        progressLayer.add(strokeLength, forKey: Animation.Indeternimate.strokeGrow)
        progressLayer.add(finalSpin, forKey: Animation.Indeternimate.strokeSpin)
        CATransaction.commit()
    }

    // MARK: - Appearance

    public var progressTintColor: UIColor? {
        didSet {
            updateColors()
        }
    }

    public var trackTintColor: UIColor? {
        didSet {
            updateColors()
        }
    }

    public var lineWidth: CGFloat = 2 {
        didSet {
            trackLayer.lineWidth = lineWidth
            progressLayer.lineWidth = lineWidth
        }
    }

    private func updateColors() {
        // Use `self.tintColor` if `progressTintColor` isn't set.
        let progressColor = progressTintColor ?? tintColor!
        progressLayer.strokeColor = progressColor.resolvedColor(with: traitCollection).cgColor

        // Reasonable fallback for track color.
        let trackColor = trackTintColor ?? UIColor.Signal.MaterialBase.fillSecondary
        trackLayer.strokeColor = trackColor.resolvedColor(with: traitCollection).cgColor
    }

    override public func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        // Use `registerForTraitChanges()` on newer iOS versions.
        guard #available(iOS 17, *) else { return }

        // Re-resolve dynamic colors when changing between light and dark themes.
        if previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle {
            updateColors()
        }
    }

    override public func tintColorDidChange() {
        super.tintColorDidChange()

        // Progress track might be using `self.tintColor` - update if that's the case.
        updateColors()
    }

    // MARK: - UIView

    private var didBecomeActiveObservation: NotificationCenter.Observer?

    override public init(frame: CGRect) {
        super.init(frame: frame)

        setupLayers()

        // Modern alternative to `traitCollectionDidChange`.
        if #available(iOS 17, *) {
            registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: CircularProgressView, _) in
                view.updateColors()
            }
        }

        didBecomeActiveObservation = NotificationCenter.default.addObserver(
            name: UIApplication.didBecomeActiveNotification,
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.restartAnimationsIfNeeded()
            }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let didBecomeActiveObservation {
            NotificationCenter.default.removeObserver(didBecomeActiveObservation)
        }
    }

    override public func layoutSubviews() {
        super.layoutSubviews()

        updateGeometryIfNecessary()
    }

    override public var intrinsicContentSize: CGSize { .square(44) }

    // MARK: - Restarting Animations

    override public func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow != nil {
            restartAnimationsIfNeeded()
        }
    }

    private func restartAnimationsIfNeeded() {
        guard animationState == .phase2 else { return }

        animationState = .phase1(CACurrentMediaTime())
        progressLayer.removeAllAnimations()
        beginInfiniteSpin()
    }

    // MARK: - Layout

    private var trackLayer = CAShapeLayer()

    private var progressLayer = CAShapeLayer()

    private func updatePath(layer: CAShapeLayer) {
        let bounds = layer.bounds

        guard bounds.isEmpty == false else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = max(0, min(bounds.width, bounds.height) - lineWidth) / 2
        let startAngle = -CGFloat.halfPi // 12 o'clock
        let endAngle = startAngle + 2 * .pi
        let path = UIBezierPath(
            arcCenter: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: true,
        )
        layer.path = path.cgPath
    }

    private func setupLayers() {
        // Track
        trackLayer.fillColor = UIColor.clear.cgColor
        trackLayer.lineWidth = lineWidth
        trackLayer.lineCap = .round
        layer.addSublayer(trackLayer)

        // Progress
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.lineWidth = lineWidth
        progressLayer.lineCap = .round
        progressLayer.strokeEnd = 0 // starts empty
        layer.addSublayer(progressLayer)

        updateColors()
    }

    private func updateGeometryIfNecessary() {
        let layerBounds = CGRect(origin: .zero, size: layer.bounds.size)
        let layerPosition = layer.bounds.center

        if layerBounds.size != trackLayer.bounds.size {
            trackLayer.bounds = layerBounds
            trackLayer.position = layerPosition
            updatePath(layer: trackLayer)
        }

        if layerBounds.size != progressLayer.bounds.size {
            progressLayer.bounds = layerBounds
            progressLayer.position = layerPosition
            updatePath(layer: progressLayer)
        }
    }
}

#if DEBUG

private class CPVPreviewViewController: UIViewController {

    let progressView = CircularProgressView(frame: .init(origin: .zero, size: .square(44)))
    var task: Task<Void, Never>?
    var cancelButton: UIButton!

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { owsFail("") }

    override func viewDidLoad() {
        super.viewDidLoad()

        let size: CGFloat = 88
        let margin: CGFloat = 4

        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        blurView.translatesAutoresizingMaskIntoConstraints = false
        blurView.layer.cornerRadius = size / 2
        blurView.layer.masksToBounds = true
        blurView.contentView.addSubview(progressView)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            progressView.widthAnchor.constraint(equalToConstant: size),
            progressView.heightAnchor.constraint(equalToConstant: size),
            progressView.centerXAnchor.constraint(equalTo: blurView.centerXAnchor),
            progressView.centerYAnchor.constraint(equalTo: blurView.centerYAnchor),
            progressView.widthAnchor.constraint(equalTo: blurView.widthAnchor, constant: -2 * margin),
            progressView.heightAnchor.constraint(equalTo: blurView.heightAnchor, constant: -2 * margin),
        ])

        let button1 = UIButton(
            configuration: .borderedProminent(),
            primaryAction: UIAction(
                title: "Run Indeterminate",
                handler: { [weak self] _ in
                    self?.runIndeterminateAnimation()
                },
            ),
        )

        let button2 = UIButton(
            configuration: .borderedProminent(),
            primaryAction: UIAction(
                title: "Run Determinate",
                handler: { [weak self] _ in
                    self?.runDeterminateAnimation()
                },
            ),
        )

        cancelButton = UIButton(
            configuration: .borderedProminent(),
            primaryAction: UIAction(
                title: "Cancel",
                handler: { [weak self] _ in
                    self?.cancel()
                },
            ),
        )

        let buttonStack = UIStackView(arrangedSubviews: [blurView, button1, button2, cancelButton])
        buttonStack.axis = .vertical
        buttonStack.spacing = 20
        buttonStack.alignment = .center
        buttonStack.distribution = .fillProportionally
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttonStack)
        NSLayoutConstraint.activate([
            buttonStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            buttonStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func runIndeterminateAnimation() {
        reset()
        progressView.startAnimating()
    }

    func runDeterminateAnimation() {
        task?.cancel()

        task = Task {
            var progress: Float = progressView.isAnimating ? 0.1 : 0

            while progress < 1 {
                let step = Float.random(in: 0.01...0.1)
                progress = min(progress + step, 1)

                progressView.setProgress(progress, animated: true)

                let delay = UInt64.random(in: 150...500) // msec
                try? await Task.sleep(nanoseconds: delay * NSEC_PER_MSEC)
            }

            // Done
        }
    }

    func reset() {
        progressView.stopAnimating()
        progressView.progress = 0
    }

    func cancel() {
        progressView.stopAnimating()

        task?.cancel()
        task = nil
    }
}

@available(iOS 17, *)
#Preview("CVCircularProgressView") {
    CPVPreviewViewController()
}

#endif
