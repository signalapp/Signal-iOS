//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// Blocks use of the app because the device's clock is too far skewed from the
/// server's for us to connect.
public class ClockSkewAppBlockingViewController: AppBlockingViewController {

    private var deviceTimeTimer: Timer?
    private let onSubmitDebugLogs: @MainActor (UIViewController) -> Void

    public init(onSubmitDebugLogs: @escaping @MainActor (UIViewController) -> Void) {
        self.onSubmitDebugLogs = onSubmitDebugLogs

        super.init(
            headerImage: UIImage(named: "timer")!,
            title: OWSLocalizedString(
                "CLOCK_SKEW_APP_BLOCKING_TITLE",
                comment: "Title for a screen shown when the app can't be used until the user corrects their device's date and time.",
            ),
            subtitle: Self.buildSubtitle(),
        )
    }

    deinit {
        deviceTimeTimer?.invalidate()
    }

    // MARK: - Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()

        // Since the user is dead-ended here, given them a hidden affordance to
        // submit debug logs (in case something with clock-skew calculations is
        // buggy).
        let submitLogsGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(didRequestToSubmitDebugLogs),
        )
        submitLogsGesture.numberOfTapsRequired = 8
        submitLogsGesture.delaysTouchesEnded = false
        view.addGestureRecognizer(submitLogsGesture)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        subtitle = Self.buildSubtitle()

        deviceTimeTimer = Timer.scheduledTimer(
            withTimeInterval: 1,
            repeats: true,
        ) { [weak self] _ in
            self?.subtitle = Self.buildSubtitle()
        }
    }

    override public func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        deviceTimeTimer?.invalidate()
        deviceTimeTimer = nil
    }

    // MARK: -

    @objc
    private func didRequestToSubmitDebugLogs() {
        onSubmitDebugLogs(self)
    }

    // MARK: -

    /// Formats in UTC, so what we show is unambiguous regardless of the device's
    /// time zone (which may itself be wrong).
    private static let deviceTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: "UTC")!
        return formatter
    }()

    private static func buildSubtitle() -> String {
        return [
            OWSLocalizedString(
                "CLOCK_SKEW_APP_BLOCKING_SUBTITLE",
                comment: "Subtitle for a screen shown when the app can't be used until the user corrects their device's date and time.",
            ),
            String.localizedStringWithFormat(
                OWSLocalizedString(
                    "CLOCK_SKEW_APP_BLOCKING_DEVICE_TIME_FORMAT",
                    comment: "Text on a screen shown when the app can't be used until the user corrects their device's date and time. Embeds {{ the device's current date and time, in UTC }}.",
                ),
                deviceTimeFormatter.string(from: Date()),
            ),
        ].joined(separator: "\n\n")
    }
}

// MARK: -

#if DEBUG

@available(iOS 17, *)
#Preview {
    ClockSkewAppBlockingViewController(onSubmitDebugLogs: { _ in })
}

#endif
