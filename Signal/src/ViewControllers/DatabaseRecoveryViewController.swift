//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalServiceKit

class DatabaseRecoveryViewController: OWSViewController {
    private let setupSskEnvironment: () -> Promise<Void>
    private let launchApp: () -> Void

    public init(
        setupSskEnvironment: @escaping () -> Promise<Void>,
        launchApp: @escaping () -> Void
    ) {
        self.setupSskEnvironment = setupSskEnvironment
        self.launchApp = launchApp
        super.init()
    }

    // MARK: - State

    enum State: Equatable {
        case awaitingUserConfirmation
        case showingDeviceSpaceWarning
        case recovering(fractionCompleted: Double)
        case recoveryFailed
        case recoverySucceeded
    }

    private var state: State = .awaitingUserConfirmation {
        didSet {
            AssertIsOnMainThread()
            render()
        }
    }
    private var previouslyRenderedState: State?

    private var databaseFileUrl: URL { GRDBDatabaseStorageAdapter.databaseFileUrl() }

    private var currentDatabaseSize: UInt64 {
        DatabaseRecovery.databaseFileSize(forDatabaseAt: databaseFileUrl)
    }

    // MARK: - Views

    private let stackView: UIStackView = {
        let view = UIStackView()
        view.axis = .vertical
        view.distribution = .equalSpacing
        view.alignment = .center
        view.layoutMargins = .init(hMargin: 32, vMargin: 46)
        view.isLayoutMarginsRelativeArrangement = true
        return view
    }()

    private let headlineLabel: UILabel = {
        let label = UILabel()
        label.font = .ows_dynamicTypeTitle2.ows_semibold
        label.textColor = Theme.primaryTextColor
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = .ows_dynamicTypeBody2
        label.textColor = Theme.secondaryTextAndIconColor
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private var databaseCorruptedImage: UIImageView {
        let view = UIImageView()
        view.image = UIImage(named: "database-corrupted")
        view.autoSetDimensions(to: .init(width: 62, height: 88))
        return view
    }

    private var databaseRecoveredImage: UIImageView {
        let view = UIImageView()
        view.image = UIImage(named: "database-recovered")
        view.autoSetDimensions(to: .init(width: 62, height: 88))
        return view
    }

    private lazy var progressStack: UIStackView = {
        let view = UIStackView(arrangedSubviews: [
            progressLabel,
            UIView.spacer(withHeight: 20),
            progressBar
        ])
        view.axis = .vertical
        view.distribution = .equalSpacing
        view.alignment = .center

        progressLabel.autoPinWidthToSuperviewMargins()
        progressBar.autoPinWidthToSuperviewMargins()

        return view
    }()

    private lazy var progressLabel: UILabel = {
        let label = UILabel()
        label.font = .ows_dynamicTypeBody2
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var progressBar: UIProgressView = {
        let bar = UIProgressView()
        bar.progressTintColor = .ows_accentBlue
        return bar
    }()

    // MARK: - View callbacks

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()

        // Users can submit logs if an error occurs during recovery. Unfortunately, some users
        // experience crashes and never get to this stage. This lightweight solution lets users
        // submit debug logs in those situations. (We do something similar during onboarding.)
        let submitLogsGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(didRequestToSubmitDebugLogs)
        )
        submitLogsGesture.numberOfTapsRequired = 8
        submitLogsGesture.delaysTouchesEnded = false
        stackView.addGestureRecognizer(submitLogsGesture)

        render()
    }

    // MARK: - Events

    @objc
    private func didTapContinueToStartRecovery() {
        switch state {
        case .awaitingUserConfirmation:
            if hasApproximatelyEnoughDiskSpace() {
                attemptRecovery()
            } else {
                state = .showingDeviceSpaceWarning
            }
        default:
            owsFailDebug("Continue was tapped on the wrong screen")
        }
    }

    @objc
    private func didTapToExportDatabase() {
        owsAssert(DebugFlags.internalSettings, "Only internal users can export databases")
        SignalApp.showExportDatabaseUI(from: self)
    }

    @objc
    private func didTapContinueToBypassStorageWarning() {
        switch state {
        case .showingDeviceSpaceWarning:
            attemptRecovery()
        default:
            owsFailDebug("Button was tapped on the wrong screen")
        }
    }

    @objc
    private func didTapToResetSignal() {
        OWSActionSheets.showConfirmationAlert(
            title: NSLocalizedString(
                "DATABASE_RECOVERY_RECOVERY_FAILED_RESET_APP_CONFIRMATION_TITLE",
                comment: "The user has tried to recover their data after it was lost due to corruption. (They have not been hacked.) If they want to delete the app and restart, they will be presented with a confirmation dialog. This is the title of that dialog."
            ),
            message: NSLocalizedString(
                "DATABASE_RECOVERY_RECOVERY_FAILED_RESET_APP_CONFIRMATION_DESCRIPTION",
                comment: "The user has tried to recover their data after it was lost due to corruption. (They have not been hacked.) If they want to delete the app and restart, they will be presented with a confirmation dialog. This is the description text in that dialog."
            ),
            proceedTitle: NSLocalizedString(
                "DATABASE_RECOVERY_RECOVERY_FAILED_RESET_APP_CONFIRMATION_CONFIRM",
                comment: "The user has tried to recover their data after it was lost due to corruption. (They have not been hacked.) If they want to delete the app and restart, they will be presented with a confirmation dialog. This is the final button they will press before their data is reset."
            ),
            proceedStyle: .destructive
        ) { _ in
            SignalApp.resetAppDataWithUI()
        }
    }

    @objc
    private func didRequestToSubmitDebugLogs() {
        self.dismiss(animated: true) {
            let supportTag = String(describing: LaunchFailure.databaseCorruptedAndMightBeRecoverable)
            DebugLogs.submitLogs(withSupportTag: supportTag)
        }
    }

    private func attemptRecovery() {
        switch state {
        case .recovering:
            owsFailDebug("Already recovering")
            return
        default:
            break
        }

        state = .recovering(fractionCompleted: 0)

        let progress = Progress(totalUnitCount: 2)
        let needsDumpAndRestore: Bool

        switch DatabaseCorruptionState(userDefaults: userDefaults).status {
        case .notCorrupted:
            owsFailDebug("Database was not corrupted! Why are we on this screen?")
            state = .recoverySucceeded
            return
        case .corrupted:
            needsDumpAndRestore = true
        case .corruptedButAlreadyDumpedAndRestored:
            needsDumpAndRestore = false
        }

        let progressObserver = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] _, _ in
            self?.didFractionCompletedChange(fractionCompleted: progress.fractionCompleted)
        }

        firstly(on: DispatchQueue.sharedUserInitiated) {
            if needsDumpAndRestore {
                let dumpAndRestore = DatabaseRecovery.DumpAndRestore(databaseFileUrl: self.databaseFileUrl)
                progress.addChild(dumpAndRestore.progress, withPendingUnitCount: 1)
                do {
                    try dumpAndRestore.run()
                } catch {
                    return Promise<Void>(error: error)
                }
                DatabaseCorruptionState.flagCorruptedDatabaseAsDumpedAndRestored(userDefaults: self.userDefaults)
            } else {
                progress.completedUnitCount += 1
            }
            return Promise.value(())
        }.then(on: DispatchQueue.sharedUserInitiated) {
            self.setupSskEnvironment()
        }.then(on: DispatchQueue.sharedUserInitiated) {
            let manualRecreation = DatabaseRecovery.ManualRecreation(databaseStorage: SDSDatabaseStorage.shared)
            progress.addChild(manualRecreation.progress, withPendingUnitCount: 1)
            manualRecreation.run()

            DatabaseCorruptionState.flagDatabaseAsRecoveredFromCorruption(userDefaults: self.userDefaults)

            return Promise.value(())
        }.done(on: DispatchQueue.main) { [weak self] in
            guard let self = self else { return }
            self.state = .recoverySucceeded
        }.ensure {
            progressObserver.invalidate()
        }.catch(on: DispatchQueue.main) { [weak self] error in
            self?.didRecoveryFail(with: error)
        }
    }

    private func didFractionCompletedChange(fractionCompleted: Double) {
        switch state {
        case .awaitingUserConfirmation, .showingDeviceSpaceWarning:
            owsFailDebug("Unexpectedly got a progress event")
            fallthrough
        case .recovering:
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.state = .recovering(fractionCompleted: fractionCompleted)
            }
        case .recoveryFailed, .recoverySucceeded:
            owsFailDebug("Unexpectedly got a progress event")
        }
    }

    private func didRecoveryFail(with error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let error = error as? DatabaseRecoveryError {
                switch error {
                case .ranOutOfDiskSpace:
                    self.state = .showingDeviceSpaceWarning
                case .unrecoverablyCorrupted:
                    self.state = .recoveryFailed
                }
            } else {
                owsFailDebug("\(error)")
                self.state = .recoveryFailed
            }
        }
    }

    @objc
    private func didTapLaunchApp() {
        switch state {
        case .recoverySucceeded:
            dismiss(animated: true) {
                self.launchApp()
            }
        default:
            owsFailDebug("Button was tapped on the wrong screen")
        }
    }

    // MARK: - Top-level renderers

    private func render() {
        stackView.backgroundColor = Theme.backgroundColor

        switch state {
        case .awaitingUserConfirmation:
            renderAwaitingUserConfirmation()
        case .showingDeviceSpaceWarning:
            renderDeviceSpaceWarning()
        case let .recovering(ratioComplete):
            renderRecovering(fractionCompleted: ratioComplete)
        case .recoveryFailed:
            renderRecoveryFailed()
        case .recoverySucceeded:
            renderRecoverySucceeded()
        }

        previouslyRenderedState = state
    }

    private func renderAwaitingUserConfirmation() {
        guard previouslyRenderedState != .awaitingUserConfirmation else { return }

        stackView.removeAllSubviews()

        headlineLabel.text = NSLocalizedString(
            "DATABASE_RECOVERY_AWAITING_USER_CONFIRMATION_TITLE",
            comment: "In some cases, the user's message history can become corrupted, and a recovery interface is shown. The user has not been hacked and may be confused by this interface, so try to avoid using terms like \"database\" or \"corrupted\"—terms like \"message history\" are better. This is the title on the first screen of this interface, which gives them some information and asks them to continue."
        )
        stackView.addArrangedSubview(headlineLabel)

        descriptionLabel.text = NSLocalizedString(
            "DATABASE_RECOVERY_AWAITING_USER_CONFIRMATION_DESCRIPTION",
            comment: "In some cases, the user's message history can become corrupted, and a recovery interface is shown. The user has not been hacked and may be confused by this interface, so keep that in mind. This is the description on the first screen of this interface, which gives them some information and asks them to continue."
        )
        stackView.addArrangedSubview(descriptionLabel)

        stackView.addArrangedSubview(databaseCorruptedImage)

        if DebugFlags.internalSettings {
            let exportDatabaseButton = button(
                title: "Export Database (internal)",
                selector: #selector(didTapToExportDatabase)
            )
            stackView.addArrangedSubview(exportDatabaseButton)
            exportDatabaseButton.autoPinWidthToSuperviewMargins()
        }

        let continueButton = button(
            title: CommonStrings.continueButton,
            selector: #selector(didTapContinueToStartRecovery)
        )
        stackView.addArrangedSubview(continueButton)
        continueButton.autoPinWidthToSuperviewMargins()

        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func renderDeviceSpaceWarning() {
        guard previouslyRenderedState != .showingDeviceSpaceWarning else { return }

        headlineLabel.text = NSLocalizedString(
            "DATABASE_RECOVERY_MORE_STORAGE_SPACE_NEEDED_TITLE",
            comment: "On the database recovery screen, if the user's device storage is nearly full, Signal will not be able to recover the database. A warning screen, which can be bypassed if the user wishes, will be shown. This is the title of that screen."
        )

        descriptionLabel.text = {
            let labelFormat = NSLocalizedString(
                "DATABASE_RECOVERY_MORE_STORAGE_SPACE_NEEDED_DESCRIPTION",
                comment: "On the database recovery screen, if the user's device storage is nearly full, Signal will not be able to recover the database. A warning screen, which can be bypassed if the user wishes, will be shown. This is the line of text on that screen. Embeds an amount like \"2GB\"."
            )
            let formattedBytes = ByteCountFormatter().string(for: currentDatabaseSize) ?? {
                owsFailDebug("Could not format the database size for some reason")
                return String(currentDatabaseSize)
            }()
            return String(format: labelFormat, formattedBytes)
        }()

        let continueButton = button(
            title: NSLocalizedString(
                "DATABASE_RECOVERY_MORE_STORAGE_SPACE_NEEDED_CONTINUE_ANYWAY",
                comment: "On the database recovery screen, if the user's device storage is nearly full, Signal will not be able to recover the database. A warning screen, which can be bypassed if the user wishes, will be shown. This is the text on the button to bypass the warning."
            ),
            selector: #selector(didTapContinueToBypassStorageWarning)
        )

        stackView.removeAllSubviews()
        stackView.addArrangedSubviews([
            headlineLabel,
            descriptionLabel,
            continueButton
        ])

        continueButton.autoPinWidthToSuperviewMargins()

        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func renderRecovering(fractionCompleted: Double) {
        switch previouslyRenderedState {
        case .recovering:
            break
        default:
            headlineLabel.text = NSLocalizedString(
                "DATABASE_RECOVERY_RECOVERY_IN_PROGRESS_TITLE",
                comment: "On the database recovery screen, this is the title shown as the user's data is being recovered."
            )

            descriptionLabel.text = NSLocalizedString(
                "DATABASE_RECOVERY_RECOVERY_IN_PROGRESS_DESCRIPTION",
                comment: "On the database recovery screen, this is the description text shown as the user's data is being recovered."
            )

            progressBar.setProgress(0, animated: false)
            progressBar.trackTintColor = Theme.isDarkThemeEnabled ? .ows_gray90 : .ows_gray05

            stackView.removeAllSubviews()
            stackView.addArrangedSubviews([
                headlineLabel,
                descriptionLabel,
                progressStack
            ])

            progressStack.autoPinWidthToSuperviewMargins()

            UIApplication.shared.isIdleTimerDisabled = true
        }

        progressLabel.text = Self.render(fractionCompleted: fractionCompleted)

        progressBar.setProgress(Float(fractionCompleted), animated: false)
    }

    private func renderRecoveryFailed() {
        guard previouslyRenderedState != .recoveryFailed else { return }

        headlineLabel.text = NSLocalizedString(
            "DATABASE_RECOVERY_RECOVERY_FAILED_TITLE",
            comment: "The user has tried to recover their data after it was lost due to corruption. (They have not been hacked.) This is the title on the screen where we show an error message."
        )

        descriptionLabel.text = NSLocalizedString(
            "DATABASE_RECOVERY_RECOVERY_FAILED_DESCRIPTION",
            comment: "The user has tried to recover their data after it was lost due to corruption. (They have not been hacked.) This is the description on the screen where we show an error message."
        )

        let resetSignalButton = self.button(
            title: NSLocalizedString(
                "DATABASE_RECOVERY_RECOVERY_FAILED_RESET_APP_BUTTON",
                comment: "The user has tried to recover their data after it was lost due to corruption. (They have not been hacked.) This button lets them delete all of their data."
            ),
            selector: #selector(didTapToResetSignal),
            backgroundColor: .ows_accentRed
        )

        let submitDebugLogsButton = self.button(
            title: NSLocalizedString(
                "DATABASE_RECOVERY_RECOVERY_FAILED_SUBMIT_DEBUG_LOG_BUTTON",
                comment: "The user has tried to recover their data after it was lost due to corruption. (They have not been hacked.) They were asked to submit a debug log. This is the button that submits this log."
            ),
            selector: #selector(didRequestToSubmitDebugLogs)
        )

        stackView.removeAllSubviews()
        stackView.addArrangedSubviews([
            headlineLabel,
            descriptionLabel,
            databaseCorruptedImage,
            resetSignalButton,
            submitDebugLogsButton
        ])

        resetSignalButton.autoPinWidthToSuperviewMargins()
        submitDebugLogsButton.autoPinWidthToSuperviewMargins()

        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func renderRecoverySucceeded() {
        guard previouslyRenderedState != .recoverySucceeded else { return }

        headlineLabel.text = NSLocalizedString(
            "DATABASE_RECOVERY_RECOVERY_SUCCEEDED_TITLE",
            comment: "The user has successfully recovered their database after it was lost due to corruption. (They have not been hacked.) This is the title on the screen that tells them things worked."
        )

        descriptionLabel.text = NSLocalizedString(
            "DATABASE_RECOVERY_RECOVERY_SUCCEEDED_DESCRIPTION",
            comment: "The user has successfully recovered their database after it was lost due to corruption. (They have not been hacked.) This is the description on the screen that tells them things worked."
        )

        let launchAppButton = button(
            title: CommonStrings.continueButton,
            selector: #selector(didTapLaunchApp)
        )

        stackView.removeAllSubviews()
        stackView.addArrangedSubviews([
            headlineLabel,
            descriptionLabel,
            databaseRecoveredImage,
            launchAppButton
        ])

        launchAppButton.autoPinWidthToSuperviewMargins()

        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Utilities

    private var userDefaults: UserDefaults { CurrentAppContext().appUserDefaults() }

    /// Determine whether the user has *approximately* enough space for recovery.
    ///
    /// The heuristic: do we have N remaining bytes, where N is the current size of the database?
    ///
    /// - Returns: `true` if the user has approximately enough disk space, or if any part of the check fails. `false` if they do not have enough disk space.
    private func hasApproximatelyEnoughDiskSpace() -> Bool {
        do {
            let freeSpace = try OWSFileSystem.freeSpaceInBytes(forPath: databaseFileUrl)
            return freeSpace >= currentDatabaseSize
        } catch {
            owsFailDebug("\(error)")
            return true
        }
    }

    private func button(title: String, selector: Selector, backgroundColor: UIColor = .ows_accentBlue) -> UIView {
        let button = OWSFlatButton.button(
            title: title,
            font: UIFont.ows_dynamicTypeBody.ows_semibold,
            titleColor: .white,
            backgroundColor: backgroundColor,
            target: self,
            selector: selector
        )
        button.autoSetHeightUsingFont()
        button.cornerRadius = 8
        return button
    }

    static func render(fractionCompleted: Double) -> String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .percent
        guard let result = numberFormatter.string(for: fractionCompleted) else {
            owsFailDebug("Unable to render ratio with number formatter")
            return ""
        }
        return result
    }
}
