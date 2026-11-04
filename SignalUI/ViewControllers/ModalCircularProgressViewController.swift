//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// A modal, determinate circular progress indicator for async work.
public class ModalCircularProgressViewController: OWSViewController {

    /// Present the modal and run the given work behind it, dismissing the modal
    /// and propagating the result when the work finishes.
    ///
    /// Tapping Cancel cancels the task running the work.
    ///
    /// - Parameter progressUpdates
    /// Progress of the work, as a fraction from 0 to 1.
    public static func presentAndRun<T>(
        from presenter: UIViewController,
        title: String,
        progressUpdates: AsyncStream<Float>,
        work: @escaping () async throws -> T,
    ) async throws -> T {
        let modal = ModalCircularProgressViewController(title: title)
        await withCheckedContinuation { continuation in
            presenter.present(modal, animated: true) {
                continuation.resume()
            }
        }

        let progressTask = Task { @MainActor in
            for await progress in progressUpdates {
                modal.updateProgress(percentComplete: progress)
            }
        }

        let workTask = Task {
            try await work()
        }
        modal.cancelBlock = { workTask.cancel() }

        let result = await workTask.result
        progressTask.cancel()

        await withCheckedContinuation { continuation in
            modal.dismiss(animated: true) {
                continuation.resume()
            }
        }

        return try result.get()
    }

    // MARK: -

    private var cancelBlock: (() -> Void)?

    private init(title: String) {
        super.init()

        self.title = title
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    private func updateProgress(percentComplete: Float) {
        progressView.setProgress(percentComplete, animated: true)
        percentCompleteLabel.text = String.nonPluralLocalizedStringWithFormat(
            OWSLocalizedString(
                "MODAL_CIRCULAR_PROGRESS_PERCENT_COMPLETE",
                comment: "Label on a progress modal indicating how far along some work is. Embeds {{ formatted percentage }}.",
            ),
            percentComplete.formatted(.owsPercent()),
        )
    }

    private func didTapCancel() {
        titleLabel.text = OWSLocalizedString(
            "MODAL_CIRCULAR_PROGRESS_CANCELLING_TITLE",
            comment: "Title for a progress modal shown after the user taps Cancel, while the work is being cancelled.",
        )
        cancelButton.isEnabled = false
        cancelBlock?()
    }

    // MARK: - Views

    private lazy var progressView: CircularProgressView = {
        let view = CircularProgressView(frame: .zero)
        view.lineWidth = 4
        view.progressTintColor = .Signal.accent
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 48),
            view.heightAnchor.constraint(equalTo: view.widthAnchor),
        ])
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.text = title
        label.font = .dynamicTypeHeadline
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .Signal.label
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var percentCompleteLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeSubheadline.monospaced()
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .Signal.label
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var cancelButton: UIButton = {
        let button = UIButton(
            configuration: .mediumBorderless(title: CommonStrings.cancelButton),
            primaryAction: UIAction { [weak self] _ in
                self?.didTapCancel()
            },
        )
        return button
    }()

    private lazy var contentStack: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [
            progressView,
            titleLabel,
            percentCompleteLabel,
            cancelButton,
        ])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 8
        stackView.setCustomSpacing(20, after: progressView)
        stackView.setCustomSpacing(20, after: percentCompleteLabel)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 32,
            leading: 24,
            bottom: 16,
            trailing: 24,
        )
        return stackView
    }()

    private lazy var panelView: UIVisualEffectView = {
        let view: UIVisualEffectView
        if #available(iOS 26, *) {
            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.tintColor = UIColor.Signal.background.withAlphaComponent(2 / 3)
            view = UIVisualEffectView(effect: glassEffect)
            view.cornerConfiguration = .uniformCorners(radius: .fixed(36))
        } else {
            view = UIVisualEffectView(effect: UIBlurEffect(style: .prominent))
            view.layer.cornerRadius = 28
        }
        view.clipsToBounds = true
        return view
    }()

    // MARK: -

    override public func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.backdrop

        panelView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panelView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        panelView.contentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            panelView.centerXAnchor.constraint(equalTo: contentLayoutGuide.centerXAnchor),
            panelView.centerYAnchor.constraint(equalTo: contentLayoutGuide.centerYAnchor),
            panelView.widthAnchor.constraint(equalToConstant: 280),

            contentStack.topAnchor.constraint(equalTo: panelView.contentView.topAnchor),
            contentStack.leadingAnchor.constraint(equalTo: panelView.contentView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: panelView.contentView.trailingAnchor),
            contentStack.bottomAnchor.constraint(equalTo: panelView.contentView.bottomAnchor),
        ])

        updateProgress(percentComplete: 0)
    }
}

// MARK: -

#if DEBUG

private class ModalCircularProgressPreviewViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        let exportButton = UIButton(
            configuration: .largePrimary(title: "Start"),
            primaryAction: UIAction { [weak self] _ in
                self?.runFakeWork()
            },
        )
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(exportButton)
        NSLayoutConstraint.activate([
            exportButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            exportButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    private func runFakeWork() {
        let (progressUpdates, progressContinuation) = AsyncStream<Float>.makeStream()

        Task {
            try? await ModalCircularProgressViewController.presentAndRun(
                from: self,
                title: "Doing work…",
                progressUpdates: progressUpdates,
            ) {
                for step in 1...50 {
                    try await Task.sleep(nanoseconds: 0.1.clampedNanoseconds)
                    progressContinuation.yield(Float(step) / 50)
                }
            }
        }
    }
}

@available(iOS 17, *)
#Preview {
    ModalCircularProgressPreviewViewController()
}

#endif
