//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

class DisappearingMessagesTimerSettingsViewController: OWSTableViewController2 {
    let thread: TSThread?
    let originalConfiguration: OWSDisappearingMessagesConfiguration
    var configuration: OWSDisappearingMessagesConfiguration
    let completion: (OWSDisappearingMessagesConfiguration) -> Void
    let isUniversal: Bool
    let useCustomPicker: Bool
    private lazy var pickerView = CustomTimePicker { [weak self] duration in
        guard let self = self else { return }
        self.configuration = self.originalConfiguration.copyAsEnabled(withDurationSeconds: duration)
        self.updateNavigation()
    }

    init(
        thread: TSThread? = nil,
        configuration: OWSDisappearingMessagesConfiguration,
        isUniversal: Bool = false,
        useCustomPicker: Bool = false,
        completion: @escaping (OWSDisappearingMessagesConfiguration) -> Void
    ) {
        self.thread = thread
        self.originalConfiguration = configuration
        self.configuration = configuration
        self.isUniversal = isUniversal
        self.useCustomPicker = useCustomPicker
        self.completion = completion

        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString(
            "DISAPPEARING_MESSAGES",
            comment: "table cell label in conversation settings"
        )

        defaultSeparatorInsetLeading = Self.cellHInnerMargin + 24 + OWSTableItem.iconSpacing

        if useCustomPicker {
            self.configuration = self.originalConfiguration.copyAsEnabled(withDurationSeconds: pickerView.selectedDuration)
        }

        updateNavigation()
        updateTableContents()
    }

    private var hasUnsavedChanges: Bool {
        originalConfiguration.asToken != configuration.asToken
    }

    // Don't allow interactive dismiss when there are unsaved changes.
    override var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set {}
    }

    private func updateNavigation() {
        if !useCustomPicker {
            navigationItem.leftBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .cancel,
                target: self,
                action: #selector(didTapCancel),
                accessibilityIdentifier: "cancel_button"
            )
        }

        if hasUnsavedChanges {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: CommonStrings.setButton,
                style: .done,
                target: self,
                action: #selector(didTapDone),
                accessibilityIdentifier: "set_button"
            )
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    func updateTableContents() {
        let contents = OWSTableContents()
        defer { self.contents = contents }

        let footerHeaderSection = OWSTableSection()
        footerHeaderSection.footerTitle = isUniversal
            ? NSLocalizedString(
                "DISAPPEARING_MESSAGES_UNIVERSAL_DESCRIPTION",
                comment: "subheading in privacy settings"
            )
            : NSLocalizedString(
                "DISAPPEARING_MESSAGES_DESCRIPTION",
                comment: "subheading in conversation settings"
            )
        contents.addSection(footerHeaderSection)

        guard !useCustomPicker else {
            let section = OWSTableSection()
            section.add(.init(
                customCellBlock: { [weak self] in
                    let cell = OWSTableItem.newCell()
                    guard let self = self else { return cell }

                    cell.selectionStyle = .none
                    cell.contentView.addSubview(self.pickerView)
                    self.pickerView.autoPinEdgesToSuperviewMargins()

                    return cell
                },
                actionBlock: {}
            ))
            contents.addSection(section)
            return
        }

        let section = OWSTableSection()
        section.add(.actionItem(
            icon: configuration.isEnabled ? .empty : .accessoryCheckmark,
            name: CommonStrings.switchOff,
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "timer_off"),
            actionBlock: { [weak self] in
                guard let self = self else { return }
                self.configuration = self.originalConfiguration.copy(withIsEnabled: false)
                self.updateNavigation()
                self.updateTableContents()
            }
        ))

        for duration in disappearingMessagesDurations {
            section.add(.actionItem(
                icon: (configuration.isEnabled && duration == configuration.durationSeconds) ? .accessoryCheckmark : .empty,
                name: DateUtil.formatDuration(seconds: duration, useShortFormat: false),
                accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "timer_\(duration)"),
                actionBlock: { [weak self] in
                    guard let self = self else { return }
                    self.configuration = self.originalConfiguration.copyAsEnabled(withDurationSeconds: duration)
                    self.updateNavigation()
                    self.updateTableContents()
                }
            ))
        }

        let isCustomTime = configuration.isEnabled && !disappearingMessagesDurations.contains(configuration.durationSeconds)

        section.add(.disclosureItem(
            icon: isCustomTime ? .accessoryCheckmark : .empty,
            name: NSLocalizedString(
                "DISAPPEARING_MESSAGES_CUSTOM_TIME",
                comment: "Disappearing message option to define a custom time"
            ),
            accessoryText: isCustomTime ? DateUtil.formatDuration(seconds: configuration.durationSeconds, useShortFormat: false) : nil,
            accessibilityIdentifier: UIView.accessibilityIdentifier(in: self, name: "timer_custom"),
            actionBlock: { [weak self] in
                guard let self = self else { return }
                let vc = DisappearingMessagesTimerSettingsViewController(
                    thread: self.thread,
                    configuration: self.originalConfiguration,
                    isUniversal: self.isUniversal,
                    useCustomPicker: true,
                    completion: self.completion
                )
                self.navigationController?.pushViewController(vc, animated: true)
            }
        ))

        contents.addSection(section)
    }

    var disappearingMessagesDurations: [UInt32] {
        return OWSDisappearingMessagesConfiguration.presetDurationsSeconds().map { $0.uint32Value }.reversed()
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
        let configuration = self.configuration

        // We use this view some places that don't have a thread like the
        // new group view and the universal timer in privacy settings. We
        // only need to do the extra "save" logic to apply the timer
        // immediately if we have a thread.
        guard let thread = thread, hasUnsavedChanges else {
            completion(configuration)
            dismiss(animated: true)
            return
        }

        GroupViewUtils.updateGroupWithActivityIndicator(
            fromViewController: self,
            withThread: thread,
            updateDescription: "Update disappearing messages configuration",
            updateBlock: { () -> Promise<Void> in
                // We're sending a message, so we're accepting any pending message request.
                ThreadUtil.addThreadToProfileWhitelistIfEmptyOrPendingRequestAndSetDefaultTimerWithSneakyTransaction(thread: thread)

                return GroupManager.localUpdateDisappearingMessages(thread: thread,
                                                                    disappearingMessageToken: configuration.asToken)
            },
            completion: { [weak self] _ in
                self?.completion(configuration)
                self?.dismiss(animated: true)
            }
        )
    }
}

private class CustomTimePicker: UIPickerView, UIPickerViewDataSource, UIPickerViewDelegate {
    enum Component: Int {
        case duration = 0
        case unit = 1
    }

    enum Unit: Int {
        case second = 0
        case minute = 1
        case hour = 2
        case day = 3
        case week = 4

        var maxValue: Int {
            switch self {
            case .second: return 59
            case .minute: return 59
            case .hour: return 23
            case .day: return 6
            case .week: return 4
            }
        }

        var name: String {
            switch self {
            case .second: return NSLocalizedString(
                "DISAPPEARING_MESSAGES_SECONDS",
                comment: "The unit for a number of seconds"
            )
            case .minute: return NSLocalizedString(
                "DISAPPEARING_MESSAGES_MINUTES",
                comment: "The unit for a number of minutes"
            )
            case .hour: return NSLocalizedString(
                "DISAPPEARING_MESSAGES_HOURS",
                comment: "The unit for a number of hours"
            )
            case .day: return NSLocalizedString(
                "DISAPPEARING_MESSAGES_DAYS",
                comment: "The unit for a number of days"
            )
            case .week: return NSLocalizedString(
                "DISAPPEARING_MESSAGES_WEEKS",
                comment: "The unit for a number of weeks"
            )
            }
        }

        var interval: TimeInterval {
            switch self {
            case .second: return kSecondInterval
            case .minute: return kMinuteInterval
            case .hour: return kHourInterval
            case .day: return kDayInterval
            case .week: return kWeekInterval
            }
        }
    }

    var selectedUnit: Unit = .second {
        didSet {
            guard oldValue != selectedUnit else { return }
            reloadComponent(Component.duration.rawValue)
            durationChangeCallback(selectedDuration)
        }
    }
    var selectedTime: Int = 1 {
        didSet {
            guard oldValue != selectedTime else { return }
            durationChangeCallback(selectedDuration)
        }
    }
    var selectedDuration: UInt32 { UInt32(selectedUnit.interval) * UInt32(selectedTime) }

    let durationChangeCallback: (UInt32) -> Void
    init(durationChangeCallback: @escaping (UInt32) -> Void) {
        self.durationChangeCallback = durationChangeCallback
        super.init(frame: .zero)
        dataSource = self
        delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func numberOfComponents(in pickerView: UIPickerView) -> Int { 2 }

    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        switch Component(rawValue: component) {
        case .duration: return selectedUnit.maxValue
        case .unit: return 5
        default:
            owsFailDebug("Unexpected component")
            return 0
        }
    }

    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        switch Component(rawValue: component) {
        case .duration: return OWSFormat.formatInt(row + 1)
        case .unit: return (Unit(rawValue: row) ?? .second).name
        default:
            owsFailDebug("Unexpected component")
            return nil
        }
    }

    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        switch Component(rawValue: component) {
        case .duration: selectedTime = row + 1
        case .unit: selectedUnit = Unit(rawValue: row) ?? .second
        default: owsFailDebug("Unexpected component")
        }
    }
}
