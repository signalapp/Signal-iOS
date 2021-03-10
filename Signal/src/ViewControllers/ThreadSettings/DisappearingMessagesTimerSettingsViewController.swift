//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

class DisappearingMessagesTimerSettingsViewController: OWSTableViewController2 {
    let originalConfiguration: OWSDisappearingMessagesConfiguration
    var configuration: OWSDisappearingMessagesConfiguration
    let completion: (OWSDisappearingMessagesConfiguration) -> Void

    init(configuration: OWSDisappearingMessagesConfiguration, completion: @escaping (OWSDisappearingMessagesConfiguration) -> Void) {
        self.originalConfiguration = configuration
        self.configuration = configuration
        self.completion = completion

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString(
            "DISAPPEARING_MESSAGES",
            comment: "table cell label in conversation settings"
        )

        updateNavigation()
        updateTableContents()
    }

    private var hasUnsavedChanges: Bool {
        originalConfiguration.isEnabled != configuration.isEnabled || originalConfiguration.durationSeconds != configuration.durationSeconds
    }

    private func updateNavigation() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didTapCancel),
            accessibilityIdentifier: "cancel_button"
        )

        if hasUnsavedChanges {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(didTapDone),
                accessibilityIdentifier: "done_button"
            )
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    func updateTableContents() {
        let contents = OWSTableContents()

        let footerHeaderSection = OWSTableSection()
        footerHeaderSection.footerTitle = NSLocalizedString(
            "DISAPPEARING_MESSAGES_DESCRIPTION",
            comment: "subheading in conversation settings"
        )
        contents.addSection(footerHeaderSection)

        let section = OWSTableSection()
        section.add(.init(
            text: CommonStrings.switchOff,
            actionBlock: { [weak self] in
                guard let self = self else { return }
                self.configuration = self.originalConfiguration.copy(withIsEnabled: false)
                self.updateNavigation()
                self.updateTableContents()
            },
            accessoryType: configuration.isEnabled ? .none : .checkmark
        ))

        for duration in disappearingMessagesDurations {
            section.add(.init(
                text: NSString.formatDurationSeconds(duration, useShortFormat: false),
                actionBlock: { [weak self] in
                    guard let self = self else { return }
                    self.configuration = self.originalConfiguration.copyAsEnabled(withDurationSeconds: duration)
                    self.updateNavigation()
                    self.updateTableContents()
                },
                accessoryType: (configuration.isEnabled && duration == configuration.durationSeconds) ? .checkmark : .none
            ))
        }

        contents.addSection(section)

        self.contents = contents
    }

    var disappearingMessagesDurations: [UInt32] {
        return OWSDisappearingMessagesConfiguration.validDurationsSeconds().map { $0.uint32Value }.reversed()
    }

    @objc
    func didTapCancel() {
        guard hasUnsavedChanges else {
            dismiss(animated: true)
            return
        }

        OWSActionSheets.showPendingChangesActionSheet(discardAction: { [weak self] in
            self?.dismiss(animated: true)
        })
    }

    @objc
    func didTapDone() {
        completion(configuration)
        dismiss(animated: true)
    }
}
