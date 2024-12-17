//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

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
    private let labelStack = UIStackView()
    private var topLabelTimer: Timer?
    private var bottomLabelTimer: Timer?

    private var progressObserver: NSKeyValueObservation?
    var progress: Progress? {
        didSet {
            self.progressObserver = progress?
                .observe(\.fractionCompleted) { [weak self] progress, _ in
                    self?.updateProgress(progress)
                }
        }
    }

    override func loadView() {
        self.view = UIView()
        view.backgroundColor = Theme.launchScreenBackgroundColor

        self.logoView = UIImageView(image: #imageLiteral(resourceName: "signal-logo-128-launch-screen"))
        view.addSubview(logoView)

        logoView.autoCenterInSuperview()
        logoView.autoSetDimensions(to: CGSize(square: 128))

        self.topLabel = buildLabel()
        topLabel.alpha = 0
        topLabel.font = UIFont.dynamicTypeTitle2
        topLabel.text = OWSLocalizedString("DATABASE_VIEW_OVERLAY_TITLE", comment: "Title shown while the app is updating its database.")
        labelStack.addArrangedSubview(topLabel)

        self.bottomLabel = buildLabel()
        bottomLabel.alpha = 0
        bottomLabel.font = UIFont.dynamicTypeBody
        bottomLabel.text = OWSLocalizedString(
            "DATABASE_VIEW_OVERLAY_SUBTITLE",
            comment: "Subtitle shown while the app is updating its database."
        ) + "\n" + OWSLocalizedString(
            "LOADING_VIEW_CONTROLLER_DONT_CLOSE_APP",
            comment: "Shown to users while the app is loading, asking them not to close the app."
        )
        bottomLabel.textAlignment = .center
        labelStack.addArrangedSubview(bottomLabel)
        labelStack.setCustomSpacing(20, after: bottomLabel)

        progressView.setProgress(0.1, animated: false)
        progressView.alpha = 0
        labelStack.addArrangedSubview(progressView)
        labelStack.setCustomSpacing(16, after: progressView)
        progressView.autoPinWidthToSuperview(withMargin: 20, relation: .lessThanOrEqual)
        progressView.autoSetDimension(.width, toSize: 330).priority = .defaultLow

        percentCompleteLabel.alpha = 0
        percentCompleteLabel.font = {
            let metrics = UIFontMetrics(forTextStyle: .body)
            let desc = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .body)
            let font = UIFont.monospacedDigitSystemFont(ofSize: desc.pointSize, weight: .regular)
            return metrics.scaledFont(for: font)
        }()
        percentCompleteLabel.textColor = .Signal.secondaryLabel
        labelStack.addArrangedSubview(percentCompleteLabel)
        labelStack.setCustomSpacing(6, after: percentCompleteLabel)

        unitCountLabel.alpha = 0
        unitCountLabel.font = .dynamicTypeBody.monospaced()
        unitCountLabel.textColor = .Signal.secondaryLabel
        labelStack.addArrangedSubview(unitCountLabel)

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
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: .OWSApplicationDidEnterBackground,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(themeDidChange),
            name: .themeDidChange,
            object: nil
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
        bottomLabel.alpha = kMinAlpha
        UIView.animate(withDuration: 0.3) {
            self.bottomLabel.alpha = 1
            self.progress.map(self.updateProgress(_:))
        }
    }

    private func showTopLabel() {
        topLabel.layer.removeAllAnimations()
        topLabel.alpha = 0.2
        UIView.animate(withDuration: 0.9, delay: 0, options: [.autoreverse, .repeat, .curveEaseInOut], animations: {
            self.topLabel.alpha = 1.0
        }, completion: nil)
    }

    private func showBottomLabel() {
        bottomLabel.layer.removeAllAnimations()
        self.bottomLabel.alpha = 1
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

    private func updateProgress(_ progress: Progress) {
        let percentComplete = Float(progress.fractionCompleted)
        let unitCountToComplete = 0
        let unitCountCompleted = Int(Double(unitCountToComplete) * progress.fractionCompleted)

        progressView.setProgress(percentComplete, animated: true)
        percentCompleteLabel.text = String(
            format: OWSLocalizedString(
                "LINK_NEW_DEVICE_SYNC_PROGRESS_PERCENT",
                comment: "On a progress modal indicating the percent complete the sync process is. Embeds {{ formatted percentage }}"
            ),
            percentComplete.formatted(.percent.precision(.fractionLength(0)))
        )
        unitCountLabel.text = "\(unitCountCompleted.formatted(.number)) / \(unitCountToComplete.formatted(.number))"

        if percentComplete > 0 {
            percentCompleteLabel.alpha = bottomLabel.alpha
            progressView.alpha = bottomLabel.alpha
        } else {
            percentCompleteLabel.alpha = 0
            progressView.alpha = 0
        }

//        if unitCountToComplete > 0 {
//            unitCountLabel.alpha = bottomLabel.alpha
//        } else {
//            unitCountLabel.alpha = 0
//        }
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
    let progress = Progress()
    progress.totalUnitCount = 100
    let viewController = LoadingViewController()
    viewController.progress = progress

    Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
        progress.completedUnitCount += Int64.random(in: 2...8)
        if progress.fractionCompleted >= 1 {
            progress.completedUnitCount = 100
            timer.invalidate()
        }
    }

    return viewController
}
#endif
