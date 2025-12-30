//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI

// The initial presentation is intended to be indistinguishable from the Launch Screen.
// After a delay we present some "loading" UI so the user doesn't think the app is frozen.
class LoadingViewController: UIViewController {

    private var logoView: UIImageView!
    private var topLabel: UILabel!
    private var bottomLabel: UILabel!
    private var progressView = UIProgressView()
    private lazy var percentCompleteLabel = UILabel()
    private lazy var unitCountLabel = UILabel()
    private lazy var cancelButton = OWSButton()
    private let labelStack = UIStackView()
    private var topLabelTimer: Timer?
    private var bottomLabelTimer: Timer?
    private var cancelButtonTimer: Timer?

    override func loadView() {
        self.view = UIView()
        view.backgroundColor = Theme.launchScreenBackgroundColor

        self.logoView = UIImageView(image: #imageLiteral(resourceName: "signal-logo-128-launch-screen"))
        view.addSubview(logoView)

        logoView.autoCenterInSuperview()
        logoView.autoSetDimensions(to: CGSize(square: 128))

        self.topLabel = buildLabel()
        topLabel.isHiddenInStackView = true
        topLabel.font = UIFont.dynamicTypeTitle2
        topLabel.text = OWSLocalizedString("DATABASE_VIEW_OVERLAY_TITLE", comment: "Title shown while the app is updating its database.")
        labelStack.addArrangedSubview(topLabel)

        self.bottomLabel = buildLabel()
        bottomLabel.isHiddenInStackView = true
        bottomLabel.font = UIFont.dynamicTypeBody
        bottomLabel.text = OWSLocalizedString(
            "DATABASE_VIEW_OVERLAY_SUBTITLE",
            comment: "Subtitle shown while the app is updating its database.",
        ) + "\n" + OWSLocalizedString(
            "LOADING_VIEW_CONTROLLER_DONT_CLOSE_APP",
            comment: "Shown to users while the app is loading, asking them not to close the app.",
        )
        bottomLabel.textAlignment = .center
        labelStack.addArrangedSubview(bottomLabel)
        labelStack.setCustomSpacing(20, after: bottomLabel)

        progressView.setProgress(0.1, animated: false)
        progressView.isHiddenInStackView = true
        labelStack.addArrangedSubview(progressView)
        labelStack.setCustomSpacing(16, after: progressView)
        progressView.autoPinWidthToSuperview(withMargin: 20, relation: .lessThanOrEqual)
        progressView.autoSetDimension(.width, toSize: 330).priority = .defaultLow

        percentCompleteLabel.isHiddenInStackView = true
        percentCompleteLabel.font = {
            let metrics = UIFontMetrics(forTextStyle: .body)
            let desc = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            let font = UIFont.monospacedDigitSystemFont(ofSize: desc.pointSize, weight: .regular)
            return metrics.scaledFont(for: font)
        }()
        percentCompleteLabel.textColor = .Signal.secondaryLabel
        labelStack.addArrangedSubview(percentCompleteLabel)
        labelStack.setCustomSpacing(6, after: percentCompleteLabel)

        unitCountLabel.isHiddenInStackView = true
        unitCountLabel.font = .dynamicTypeBody.monospaced()
        unitCountLabel.textColor = .Signal.secondaryLabel
        labelStack.addArrangedSubview(unitCountLabel)

        cancelButton.isHiddenInStackView = true
        cancelButton.isEnabled = false
        cancelButton.titleLabel?.font = .dynamicTypeBody.monospaced()
        cancelButton.backgroundColor = .clear
        cancelButton.setTitle(CommonStrings.cancelButton, for: .normal)
        cancelButton.setTitleColor(.Signal.ultramarine, for: .normal)
        labelStack.addArrangedSubview(cancelButton)
        cancelButton.block = { [weak self] in
            self?.cancellableTask?.cancel()
            self?.setCancellableTask(nil)
        }

        labelStack.axis = .vertical
        labelStack.alignment = .center
        labelStack.spacing = 8
        view.addSubview(labelStack)

        labelStack.autoPinEdge(.top, to: .bottom, of: logoView, withOffset: 40)
        labelStack.autoPinLeadingToSuperviewMargin()
        labelStack.autoPinTrailingToSuperviewMargin()
        labelStack.setCompressionResistanceHigh()
        labelStack.setContentHuggingHigh()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: .OWSApplicationDidBecomeActive,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .themeDidChange,
            object: nil,
        )
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        // We only show the "loading" UI if it's a slow launch. Otherwise this ViewController
        // should be indistinguishable from the launch screen.
        let kTopLabelThreshold: TimeInterval = 5
        topLabelTimer = Timer.scheduledTimer(withTimeInterval: kTopLabelThreshold, repeats: false) { [weak self] _ in
            self?.showTopLabel()
        }

        let kBottomLabelThreshold: TimeInterval = 10
        bottomLabelTimer = Timer.scheduledTimer(withTimeInterval: kBottomLabelThreshold, repeats: false) { [weak self] _ in
            self?.showBottomLabelAnimated()
        }

        let kCancelButtonThreshold: TimeInterval = 60
        cancelButtonTimer?.invalidate()
        self.canShowCancelButton = false
        self.updateCancelButton()
        cancelButtonTimer = Timer.scheduledTimer(withTimeInterval: kCancelButtonThreshold, repeats: false) { [weak self] _ in
            self?.canShowCancelButton = true
            self?.updateCancelButton()
        }
    }

    // UIStackView removes hidden subviews from the layout.
    // UIStackView considers views with a sufficiently low
    // alpha to be "hidden".  This can cause layout to glitch
    // briefly when returning from background.  Therefore we
    // use a "min" alpha value when fading in labels that is
    // high enough to avoid this UIStackView behavior.
    private let kMinAlpha: CGFloat = 0.1

    private func showBottomLabelAnimated() {
        bottomLabel.layer.removeAllAnimations()
        bottomLabel.isHiddenInStackView = false
        bottomLabel.alpha = kMinAlpha
        UIView.animate(withDuration: 0.3) {
            self.bottomLabel.alpha = 1
            self.progress.map(self.updateProgress(_:))
        }
    }

    private func showTopLabel() {
        topLabel.layer.removeAllAnimations()
        topLabel.isHiddenInStackView = false
        topLabel.alpha = 0.2
        UIView.animate(withDuration: 0.9, delay: 0, options: [.autoreverse, .repeat, .curveEaseInOut], animations: {
            self.topLabel.alpha = 1.0
        }, completion: nil)
    }

    private func showBottomLabel() {
        bottomLabel.layer.removeAllAnimations()
        bottomLabel.isHiddenInStackView = false
    }

    // MARK: -

    @objc
    private func didBecomeActive() {
        AssertIsOnMainThread()

        guard viewHasEnteredBackground else {
            // If the app is returning from background, skip any
            // animations and show the top and bottom labels.
            return
        }

        topLabelTimer?.invalidate()
        topLabelTimer = nil
        bottomLabelTimer?.invalidate()
        bottomLabelTimer = nil

        showTopLabel()
        showBottomLabel()

        labelStack.layoutSubviews()
        view.layoutSubviews()
    }

    private var viewHasEnteredBackground = false

    @objc
    private func didEnterBackground() {
        AssertIsOnMainThread()

        viewHasEnteredBackground = true
    }

    @objc
    private func themeDidChange() {
        view.backgroundColor = Theme.launchScreenBackgroundColor
    }

    private var progress: OWSProgress?

    func updateProgress(_ progress: OWSProgress) {
        self.progress = progress
        let percentComplete = progress.percentComplete
        let unitCountToComplete = progress.totalUnitCount
        let unitCountCompleted = Int(Float(unitCountToComplete) * progress.percentComplete)

        progressView.setProgress(percentComplete, animated: true)
        percentCompleteLabel.text = String(
            format: OWSLocalizedString(
                "LINK_NEW_DEVICE_SYNC_PROGRESS_PERCENT",
                comment: "On a progress modal indicating the percent complete the sync process is. Embeds {{ formatted percentage }}",
            ),
            percentComplete.formatted(.percent.precision(.fractionLength(0))),
        )
        unitCountLabel.text = "\(unitCountCompleted.formatted(.number)) / \(unitCountToComplete.formatted(.number))"

        if percentComplete > 0 {
            percentCompleteLabel.alpha = bottomLabel.alpha
            progressView.alpha = bottomLabel.alpha
        } else {
            percentCompleteLabel.alpha = 0
            progressView.alpha = 0
        }

        if unitCountToComplete > 0, percentComplete > 0 {
            unitCountLabel.alpha = bottomLabel.alpha
        } else {
            unitCountLabel.alpha = 0
        }
    }

    private var cancellableTask: Task<Void, Never>?
    private var canShowCancelButton = false

    // Sets the running task that is running and which is
    // cancellable (will display a cancel button).
    // Typically this task's work is represented in `updateProgress`
    // if that has been called; its ok to set this without
    // setting progress, however.
    func setCancellableTask(_ task: Task<Void, Never>?) {
        self.cancellableTask = task
        updateCancelButton()
    }

    private func updateCancelButton() {
        if cancellableTask != nil, canShowCancelButton {
            cancelButton.isHiddenInStackView = false
            cancelButton.isEnabled = true
        } else {
            cancelButton.isHiddenInStackView = true
            cancelButton.isEnabled = false
        }
    }

    // MARK: Orientation

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

    private func buildLabel() -> UILabel {
        let label = UILabel()

        label.textColor = .Signal.label
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping

        return label
    }
}

#if DEBUG
@available(iOS 17, *)
#Preview {
    let viewController = LoadingViewController()
    let progressSink = OWSProgress.createSink { progress in
        await MainActor.run {
            viewController.updateProgress(progress)
        }
    }

    let task = Task {
        let source = await progressSink.addSource(withLabel: "count", unitCount: 100)
        while source.completedUnitCount < 100 {
            do {
                try Task.checkCancellation()
            } catch {
                source.incrementCompletedUnitCount(by: 100)
                return
            }
            try? await Task.sleep(nanoseconds: 100 * NSEC_PER_SEC)
            source.incrementCompletedUnitCount(by: UInt64.random(in: 2...8))
        }
    }

    viewController.setCancellableTask(task)

    return viewController
}
#endif
