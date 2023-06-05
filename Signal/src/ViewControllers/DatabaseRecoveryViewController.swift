//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalServiceKit
import SignalUI

class DatabaseRecoveryViewController<SetupResult>: OWSViewController {
    private let setupSskEnvironment: () -> Guarantee<SetupResult>
    private let launchApp: (SetupResult) -> Void

    public init(
        setupSskEnvironment: @escaping () -> Guarantee<SetupResult>,
        launchApp: @escaping (SetupResult) -> Void
    ) {
        self.setupSskEnvironment = setupSskEnvironment
        self.launchApp = launchApp
        super.init()
    }

    // MARK: - State

    enum State {
        case awaitingUserConfirmation
        case showingDeviceSpaceWarning
        case recovering(fractionCompleted: Double)
        case recoveryFailed
        case recoverySucceeded(SetupResult)
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
        label.font = .dynamicTypeTitle2.semibold()
        label.textColor = Theme.primaryTextColor
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let descriptionLabel: UILabel = {
        let label = UILabel()
        label.font = .dynamicTypeBody2
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
        label.font = .dynamicTypeBody2
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
            title: OWSLocalizedString(
                "DATABASE_RECOVERY_RECOVERY_FAILED_RESET_APP_CONFIRMATION_TITLE",
                comment: "The user has tried to recover their data after it was lost due to corruption. (They have not been hacked.) If they want to delete the app and restart, they will be presented with a confirmation dialog. This is the title of that dialog."
            ),
            message: OWSLocalizedString(
                "DATABASE_RECOVERY_RECOVERY_FAILED_RESET_APP_CONFIRMATION_DESCRIPTION",
                comment: "The user has tried to recover their data after it was lost due to corruption. (They have not been hacked.) If they want to delete the app and restart, they will be presented with a confirmation dialog. This is the description text in that dialog."
            ),
            proceedTitle: OWSLocalizedString(
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
            DebugLogs.submitLogsWithSupportTag(LaunchPreflightError.databaseCorruptedAndMightBeRecoverable.supportTag)
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

        // We might not run all the steps (see comment below). We could use that to adjust the
        // progress's unit count but that makes the code more complicated, so we just set it to 4
        // for simplicity.
        let progress = Progress(totalUnitCount: 4)

        let progressObserver = progress.observe(\.fractionCompleted, options: [.new]) { [weak self] _, _ in
            self?.didFractionCompletedChange(fractionCompleted: progress.fractionCompleted)
        }

        // This code is complicated because of (1) progress observation (2) promises. In practice,
        // we're basically doing this:
        //
        // If we previously did a dump-and-restore and were interrupted (unusual but possible):
        //
        // 1. Set up the environment.
        // 2. Do a manual recreate.
        // 3. Mark the database as recovered.
        //
        // Otherwise...
        //
        // 1. Try to rebuild the existing database. If that clears corruption, skip steps 2 and 4.
        // 2. Dump and restore.
        // 3. Set up the environment.
        // 4. Do a manual recreate.
        // 5. Mark the database as recovered.
        let promise: Promise<SetupResult>
        switch DatabaseCorruptionState(userDefaults: userDefaults).status {
        case .notCorrupted:
            owsFail("Database was not corrupted! Why are we on this screen?")
        case .corrupted, .readCorrupted:
            promise = firstly(on: DispatchQueue.sharedUserInitiated) { () -> Promise<Bool> in
                progress.performAsCurrent(withPendingUnitCount: 1) {
                    DatabaseRecovery.rebuildExistingDatabase(at: self.databaseFileUrl)
                }
                let integrity = progress.performAsCurrent(withPendingUnitCount: 1) {
                    return DatabaseRecovery.integrityCheck(databaseFileUrl: self.databaseFileUrl)
                }

                let shouldDumpAndRecreate: Bool
                switch integrity {
                case .ok: shouldDumpAndRecreate = false
                case .notOk: shouldDumpAndRecreate = true
                }

                if shouldDumpAndRecreate {
                    let dumpAndRestore = DatabaseRecovery.DumpAndRestore(databaseFileUrl: self.databaseFileUrl)
                    progress.addChild(dumpAndRestore.progress, withPendingUnitCount: 1)
                    do {
                        try dumpAndRestore.run()
                    } catch {
                        return Promise<Bool>(error: error)
                    }
                    DatabaseCorruptionState.flagCorruptedDatabaseAsDumpedAndRestored(userDefaults: self.userDefaults)
                } else {
                    progress.completedUnitCount += 1
                }

                return .value(shouldDumpAndRecreate)
            }.then(on: DispatchQueue.sharedUserInitiated) { shouldDumpAndRecreate in
                self.setupSskEnvironment().map(on: DispatchQueue.sharedUserInitiated) { setupResult in
                    if shouldDumpAndRecreate {
                        let manualRecreation = DatabaseRecovery.ManualRecreation(databaseStorage: SDSDatabaseStorage.shared)
                        progress.addChild(manualRecreation.progress, withPendingUnitCount: 1)
                        manualRecreation.run()
                    } else {
                        progress.completedUnitCount += 1
                    }
                    return setupResult
                }
            }
        case .corruptedButAlreadyDumpedAndRestored:
            promise = firstly(on: DispatchQueue.sharedUserInitiated) {
                self.setupSskEnvironment()
            }.map(on: DispatchQueue.sharedUserInitiated) { setupResult in
                let manualRecreation = DatabaseRecovery.ManualRecreation(databaseStorage: SDSDatabaseStorage.shared)
                progress.addChild(
                    manualRecreation.progress,
                    withPendingUnitCount: progress.remainingUnitCount
                )
                manualRecreation.run()
                return setupResult
            }
        }

        promise.done(on: DispatchQueue.main) { setupResult in
            DatabaseCorruptionState.flagDatabaseAsRecoveredFromCorruption(userDefaults: self.userDefaults)
            self.state = .recoverySucceeded(setupResult)
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
        case .recoverySucceeded(let setupResult):
            dismiss(animated: true) {
                self.launchApp(setupResult)
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
        if case .awaitingUserConfirmation = previouslyRenderedState { return }

        stackView.removeAllSubviews()

        headlineLabel.text = OWSLocalizedString(
            "DATABASE_RECOVERY_AWAITING_USER_CONFIRMATION_TITLE",
            comment: "In some cases, the user's message history can become corrupted, and a recovery interface is shown. The user has not been hacked and may be confused by this interface, so try to avoid using terms like \"database\" or \"corrupted\"—terms like \"message history\" are better. This is the title on the first screen of this interface, which gives them some information and asks them to continue."
        )
        stackView.addArrangedSubview(headlineLabel)

        descriptionLabel.text = OWSLocalizedString(
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
        if case .showingDeviceSpaceWarning = previouslyRenderedState { return }

        headlineLabel.text = OWSLocalizedString(
            "DATABASE_RECOVERY_MORE_STORAGE_SPACE_NEEDED_TITLE",
            comment: "On the database recovery screen, if the user's device storage is nearly full, Signal will not be able to recover the database. A warning screen, which can be bypassed if the user wishes, will be shown. This is the title of that screen."
        )

        descriptionLabel.text = {
            let labelFormat = OWSLocalizedString(
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
            title: OWSLocalizedString(
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
            headlineLabel.text = OWSLocalizedString(
                "DATABASE_RECOVERY_RECOVERY_IN_PROGRESS_TITLE",
                comment: "On the database recovery screen, this is the title shown as the user's data is being recovered."
            )

            descriptionLabel.text = OWSLocalizedString(
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
        if case .recoveryFailed = previouslyRenderedState { return }

        headlineLabel.text = OWSLocalizedString(
            "DATABASE_RECOVERY_RECOVERY_FAILED_TITLE",
            comment: "The user has tried to recover their data after it was lost due to corruption. (They have not been hacked.) This is the title on the screen where we show an error message."
        )

        descriptionLabel.text = OWSLocalizedString(
            "DATABASE_RECOVERY_RECOVERY_FAILED_DESCRIPTION",
            comment: "The user has tried to recover their data after it was lost due to corruption. (They have not been hacked.) This is the description on the screen where we show an error message."
        )

        let resetSignalButton = self.button(
            title: OWSLocalizedString(
                "DATABASE_RECOVERY_RECOVERY_FAILED_RESET_APP_BUTTON",
                comment: "The user has tried to recover their data after it was lost due to corruption. (They have not been hacked.) This button lets them delete all of their data."
            ),
            selector: #selector(didTapToResetSignal),
            backgroundColor: .ows_accentRed
        )

        let submitDebugLogsButton = self.button(
            title: OWSLocalizedString(
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
        if case .recoverySucceeded = previouslyRenderedState { return }

        headlineLabel.text = OWSLocalizedString(
            "DATABASE_RECOVERY_RECOVERY_SUCCEEDED_TITLE",
            comment: "The user has successfully recovered their database after it was lost due to corruption. (They have not been hacked.) This is the title on the screen that tells them things worked."
        )

        descriptionLabel.text = OWSLocalizedString(
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
            font: UIFont.dynamicTypeBody.semibold(),
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
