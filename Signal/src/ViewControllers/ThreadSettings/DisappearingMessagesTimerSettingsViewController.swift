//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

class DisappearingMessagesTimerSettingsViewController: HostingController<DisappearingMessagesTimerSettingsView> {
    enum SettingsMode {
        case chat(thread: TSThread)
        case newGroup
        case universal
    }

    private let initialConfiguration: OWSDisappearingMessagesConfiguration
    private var selectedConfiguration: OWSDisappearingMessagesConfiguration
    private let settingsMode: SettingsMode
    private let completion: (OWSDisappearingMessagesConfiguration) -> Void

    private let viewModel: DisappearingMessagesTimerSettingsViewModel

    private lazy var setButton: UIBarButtonItem = .setButton { [weak self] in
        self?.completeAndDismiss()
    }

    init(
        initialConfiguration: OWSDisappearingMessagesConfiguration,
        settingsMode: SettingsMode,
        completion: @escaping (OWSDisappearingMessagesConfiguration) -> Void,
    ) {
        self.initialConfiguration = initialConfiguration
        self.selectedConfiguration = initialConfiguration
        self.settingsMode = settingsMode
        self.completion = completion

        self.viewModel = DisappearingMessagesTimerSettingsViewModel(
            initialDurationSeconds: initialConfiguration.durationSeconds,
            settingsMode: settingsMode,
        )

        super.init(wrappedView: DisappearingMessagesTimerSettingsView(viewModel: viewModel))

        title = OWSLocalizedString(
            "DISAPPEARING_MESSAGES",
            comment: "table cell label in conversation settings",
        )
        OWSTableViewController2.removeBackButtonText(viewController: self)

        viewModel.actionsDelegate = self

        navigationItem.leftBarButtonItem = .cancelButton(
            dismissingFrom: self,
            hasUnsavedChanges: { [weak self] in self?.hasUnsavedChanges },
        )

        navigationItem.rightBarButtonItem = self.setButton

        updateNavigationItem()
    }

    private var hasUnsavedChanges: Bool {
        return initialConfiguration.asToken != selectedConfiguration.asToken
    }

    // Don't allow interactive dismiss when there are unsaved changes.
    override var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set {}
    }

    private func updateNavigationItem() {
        setButton.isEnabled = hasUnsavedChanges
    }

    private func completeAndDismiss() {
        let configuration = selectedConfiguration

        // We use this view some places that don't have a thread like the
        // new group view and the universal timer in privacy settings. We
        // only need to do the extra "save" logic to apply the timer
        // immediately if we have a thread.
        guard
            let thread = switch settingsMode
        {
        case .chat(let thread): thread
        case .newGroup, .universal: nil
        },
            hasUnsavedChanges
        else {
            completion(configuration)
            dismiss(animated: true)
            return
        }

        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: self,
            updateBlock: {
                let databaseStorage = SSKEnvironment.shared.databaseStorageRef
                await databaseStorage.awaitableWrite { tx in
                    // We're sending a message, so we're accepting any pending message request.
                    _ = ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequest(thread, setDefaultTimerIfNecessary: true, tx: tx)
                }
                try await self.localUpdateDisappearingMessagesConfiguration(
                    thread: thread,
                    newToken: configuration.asVersionedToken,
                )
            },
            completion: { [weak self] in
                self?.completion(configuration)
                self?.dismiss(animated: true)
            },
        )
    }

    private func localUpdateDisappearingMessagesConfiguration(
        thread: TSThread,
        newToken: VersionedDisappearingMessageToken,
    ) async throws {
        if let contactThread = thread as? TSContactThread {
            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                GroupManager.localUpdateDisappearingMessageToken(
                    newToken,
                    inContactThread: contactThread,
                    tx: tx,
                )
            }
        } else if let groupThread = thread as? TSGroupThread {
            if let groupV2Model = groupThread.groupModel as? TSGroupModelV2 {
                try await GroupManager.updateGroupV2(
                    groupModel: groupV2Model,
                    description: "Update disappearing messages",
                ) { changeSet in
                    changeSet.setNewDisappearingMessageToken(newToken.unversioned)
                }
            } else {
                throw OWSAssertionError("Cannot update disappearing message config for V1 groups!")
            }
        } else {
            throw OWSAssertionError("Unexpected thread type in disappearing message update! \(type(of: thread))")
        }
    }
}

// MARK: - DisappearingMessagesTimerSettingsViewModel.ActionsDelegate

extension DisappearingMessagesTimerSettingsViewController: DisappearingMessagesTimerSettingsViewModel.ActionsDelegate {
    fileprivate func updateForSelection(_ durationSeconds: UInt32) {
        if durationSeconds == 0 {
            selectedConfiguration = initialConfiguration.copy(
                withIsEnabled: false,
                timerVersion: initialConfiguration.timerVersion + 1,
            )
        } else {
            selectedConfiguration = initialConfiguration.copyAsEnabled(
                withDurationSeconds: durationSeconds,
                timerVersion: initialConfiguration.timerVersion + 1,
            )
        }

        updateNavigationItem()
    }

    fileprivate func showCustomTimePicker() {
        guard let navigationController else {
            owsFailDebug("Missing navigation controller!")
            return
        }

        let initialDurationSeconds: UInt32? = switch viewModel.selection {
        case .preset: nil
        case .custom(let durationSeconds): durationSeconds
        }

        let customTimePickerViewController = DisappearingMessagesCustomTimePickerViewController(
            initialDurationSeconds: initialDurationSeconds,
        ) { [self] durationSeconds in
            viewModel.selection = .custom(durationSeconds: durationSeconds)
            updateForSelection(durationSeconds)

            updateNavigationItem()
        }

        navigationController.pushViewController(customTimePickerViewController, animated: true)
    }
}

// MARK: -

private class DisappearingMessagesTimerSettingsViewModel: ObservableObject {
    protocol ActionsDelegate: AnyObject {
        func updateForSelection(_ durationSeconds: UInt32)
        func showCustomTimePicker()
    }

    struct Preset: Identifiable, Equatable {
        let localizedDescription: String
        let durationSeconds: UInt32

        var id: UInt32 { durationSeconds }
    }

    enum Selection {
        case preset(Preset)
        case custom(durationSeconds: UInt32)

        var durationSeconds: UInt32 {
            switch self {
            case .preset(let preset): preset.durationSeconds
            case .custom(let durationSeconds): durationSeconds
            }
        }
    }

    weak var actionsDelegate: ActionsDelegate?

    let presets: [Preset]
    let settingsMode: DisappearingMessagesTimerSettingsViewController.SettingsMode

    @Published var selection: Selection

    init(
        initialDurationSeconds: UInt32,
        settingsMode: DisappearingMessagesTimerSettingsViewController.SettingsMode,
    ) {
        let disabledPreset = Preset(
            localizedDescription: CommonStrings.switchOff,
            durationSeconds: 0,
        )
        let enabledPresets = OWSDisappearingMessagesConfiguration
            .presetDurationsSeconds()
            .reversed()
            .map { $0.uint32Value }
            .map { durationSeconds in
                Preset(
                    localizedDescription: DateUtil.formatDuration(seconds: durationSeconds, useShortFormat: false),
                    durationSeconds: durationSeconds,
                )
            }

        self.presets = [disabledPreset] + enabledPresets
        self.settingsMode = settingsMode

        self.selection = if let matchingPreset = presets.first(where: { $0.durationSeconds == initialDurationSeconds }) {
            .preset(matchingPreset)
        } else {
            .custom(durationSeconds: initialDurationSeconds)
        }
    }

    func setSelection(_ selection: Selection) {
        self.selection = selection
        actionsDelegate?.updateForSelection(selection.durationSeconds)
    }
}

struct DisappearingMessagesTimerSettingsView: View {
    @ObservedObject private var viewModel: DisappearingMessagesTimerSettingsViewModel

    fileprivate init(viewModel: DisappearingMessagesTimerSettingsViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        SignalList {
            Section {
                ForEach(viewModel.presets) { preset in
                    Button {
                        viewModel.setSelection(.preset(preset))
                    } label: {
                        Label {
                            Text(preset.localizedDescription)
                                .padding(.leading, -8)
                        } icon: {
                            switch viewModel.selection {
                            case .preset(let selectedPreset) where selectedPreset == preset:
                                Image(.check)
                            case .preset, .custom:
                                Color.clear
                                    .frame(width: 24)
                            }
                        }
                        .foregroundStyle(Color.Signal.label)
                    }
                    .padding(.leading, -8)
                }

                Button {
                    viewModel.actionsDelegate?.showCustomTimePicker()
                } label: {
                    HStack {
                        Label {
                            Text(OWSLocalizedString(
                                "DISAPPEARING_MESSAGES_CUSTOM_TIME",
                                comment: "Disappearing message option to define a custom time",
                            ))
                            .padding(.leading, -8)
                        } icon: {
                            switch viewModel.selection {
                            case .custom:
                                Image(.check)
                            case .preset:
                                Color.clear
                                    .frame(width: 24)
                            }
                        }
                        .foregroundStyle(Color.Signal.label)

                        Spacer()

                        switch viewModel.selection {
                        case .preset:
                            EmptyView()
                        case .custom(let durationSeconds):
                            Text(DateUtil.formatDuration(
                                seconds: durationSeconds,
                                useShortFormat: false,
                            ))
                            .foregroundStyle(Color.Signal.secondaryLabel)
                        }

                        Image(systemName: "chevron.right")
                            .foregroundStyle(Color.Signal.secondaryLabel)
                    }
                }
                .padding(.leading, -8)
            } header: {
                let headerText = switch viewModel.settingsMode {
                case .chat, .newGroup:
                    OWSLocalizedString(
                        "DISAPPEARING_MESSAGES_DESCRIPTION",
                        comment: "subheading in conversation settings",
                    )
                case .universal:
                    OWSLocalizedString(
                        "DISAPPEARING_MESSAGES_UNIVERSAL_DESCRIPTION",
                        comment: "subheading in privacy settings",
                    )
                }

                Text(headerText)
                    .textCase(.none)
                    .font(.subheadline)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                    .padding(.bottom, 16)
            }
        }
    }
}

// MARK: -

#if DEBUG

private extension DisappearingMessagesTimerSettingsViewModel {
    static func forPreview(
        settingsMode: DisappearingMessagesTimerSettingsViewController.SettingsMode,
    ) -> DisappearingMessagesTimerSettingsViewModel {
        return DisappearingMessagesTimerSettingsViewModel(
            initialDurationSeconds: 120,
            settingsMode: settingsMode,
        )
    }
}

#Preview {
    DisappearingMessagesTimerSettingsView(viewModel: .forPreview(
        settingsMode: .universal,
    ))
}

#endif
