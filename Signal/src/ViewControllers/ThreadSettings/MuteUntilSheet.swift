//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

final class MuteUntilSheet: SheetNavigationController {
    init(didConfirm: @escaping (Date) -> Void) {
        super.init(rootViewController: MuteUntilPickerViewController(didConfirm: didConfirm))
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - MuteUntilPickerViewController

private final class MuteUntilPickerViewController: NavStackSheetViewController {

    private let dateProvider: DateProvider = Date.provider
    private let didConfirm: (Date) -> Void

    init(didConfirm: @escaping (Date) -> Void) {
        self.didConfirm = didConfirm
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var stackViewInsets: UIEdgeInsets {
        .init(top: 16, leading: 16, bottom: 0, trailing: 16)
    }

    override var minimumBottomInsetIncludingSafeArea: CGFloat { 24 }

    private lazy var confirmButton: UIBarButtonItem = {
        let item = UIBarButtonItem.button(
            image: UIImage(resource: .check),
            isProminent: true,
        ) { [weak self] in
            self?.confirm()
        }
        item.accessibilityLabel = CommonStrings.muteButton
        return item
    }()

    // MARK: Pills

    private enum PickerMode {
        case date
        case time
    }

    private var pickerMode: PickerMode = .date {
        didSet {
            guard pickerMode != oldValue else { return }
            updatePickerMode(animated: true)
        }
    }

    private let pickerContainer: UIView = {
        let view = UIView()
        view.clipsToBounds = true
        return view
    }()

    private lazy var datePickerHeightConstraint = pickerContainer.heightAnchor.constraint(equalTo: datePicker.heightAnchor)
    private lazy var timePickerHeightConstraint = pickerContainer.heightAnchor.constraint(equalTo: timePicker.heightAnchor)

    private lazy var datePill = makePill { [weak self] in
        self?.pickerMode = .date
    }

    private lazy var timePill = makePill { [weak self] in
        self?.pickerMode = .time
    }

    // Using the native isSelected would change the button background color
    private func setPill(_ pill: UIButton, isSelected: Bool) {
        pill.configuration?.baseForegroundColor = isSelected ? .Signal.accent : .Signal.label
        if isSelected {
            pill.accessibilityTraits.insert(.selected)
        } else {
            pill.accessibilityTraits.remove(.selected)
        }
    }

    private func makePill(action: @escaping () -> Void) -> UIButton {
        var configuration: UIButton.Configuration = .gray()
        configuration.baseBackgroundColor = .Signal.tertiaryFill
        configuration.titleTextAttributesTransformer = .defaultFont(.dynamicTypeBodyClamped)
        return UIButton(
            configuration: configuration,
            primaryAction: UIAction { _ in action() },
        )
    }

    // MARK: Pickers

    private lazy var datePicker: UIDatePicker = {
        let picker = UIDatePicker()
        picker.datePickerMode = .date
        picker.preferredDatePickerStyle = .inline
        picker.addTarget(self, action: #selector(pickerValueDidChange), for: .valueChanged)
        return picker
    }()

    private lazy var timePicker: UIDatePicker = {
        let picker = UIDatePicker()
        picker.datePickerMode = .time
        picker.preferredDatePickerStyle = .wheels
        picker.addTarget(self, action: #selector(pickerValueDidChange), for: .valueChanged)
        return picker
    }()

    private var selectedDate: Date {
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: datePicker.date)
        let time = calendar.dateComponents([.hour, .minute], from: timePicker.date)
        components.hour = time.hour
        components.minute = time.minute
        return calendar.date(from: components).owsFailUnwrap("failed to construct date")
    }

    /// 8:00 AM on the next calendar day
    private static func defaultDate(now: Date, calendar: Calendar) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)
            .owsFailUnwrap("failed to construct date")
        return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow)
            .owsFailUnwrap("failed to construct date")
    }

    // MARK: Layout

    private static let sectionMargin: CGFloat = 16

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString(
            "MUTE_UNTIL_SHEET_TITLE",
            comment: "Title for the sheet for muting a chat's notifications until a custom date.",
        )
        navigationItem.leftBarButtonItem = .closeButton { [weak self] in
            self?.dismiss(animated: true)
        }
        navigationItem.rightBarButtonItem = confirmButton

        stackView.spacing = 16

        let muteUntilLabel = UILabel()
        muteUntilLabel.text = OWSLocalizedString(
            "MUTE_UNTIL_SHEET_MUTE_UNTIL_LABEL",
            comment: "Label next to the selected date and time on the sheet for muting a chat's notifications until a custom date.",
        )
        muteUntilLabel.font = .dynamicTypeBodyClamped
        muteUntilLabel.textColor = .Signal.label
        muteUntilLabel.setCompressionResistanceHorizontalHigh()

        let muteUntilRow = UIStackView(arrangedSubviews: [muteUntilLabel, UIView.hStretchingSpacer(), datePill, timePill])
        muteUntilRow.axis = .horizontal
        muteUntilRow.alignment = .center
        muteUntilRow.spacing = 8

        // The pickers exist in the same spot and fade in and out
        pickerContainer.addSubview(datePicker)
        pickerContainer.addSubview(timePicker)
        datePicker.autoPinEdges(toSuperviewEdgesExcludingEdge: .bottom)
        timePicker.autoPinEdges(toSuperviewEdgesExcludingEdge: .bottom)

        let sectionStack = UIStackView()
        sectionStack.addArrangedSubview(muteUntilRow)
        sectionStack.addHairline(with: .Signal.transparentSeparator)
        sectionStack.addArrangedSubview(pickerContainer)
        sectionStack.axis = .vertical
        sectionStack.spacing = 12
        sectionStack.isLayoutMarginsRelativeArrangement = true
        sectionStack.layoutMargins = .init(margin: Self.sectionMargin)
        sectionStack.backgroundColor = .Signal.secondaryGroupedBackground
        sectionStack.layer.cornerRadius = OWSTableViewController2.cellRounding
        stackView.addArrangedSubview(sectionStack)

        let timeZoneLabel = UILabel()
        let timeZoneFormat = OWSLocalizedString(
            "MUTE_UNTIL_SHEET_TIME_ZONE_FOOTER_FORMAT",
            comment: "Footer on the sheet for muting a chat's notifications until a custom date, clarifying which time zone the selected date and time are in. Embeds {{the name of the current time zone}}.",
        )
        let timeZone = TimeZone.current
        let timeZoneName = timeZone.localizedName(for: .generic, locale: .current) ?? timeZone.identifier
        timeZoneLabel.text = String.nonPluralLocalizedStringWithFormat(timeZoneFormat, timeZoneName)
        timeZoneLabel.font = .dynamicTypeFootnoteClamped
        timeZoneLabel.textColor = .Signal.secondaryLabel
        timeZoneLabel.numberOfLines = 0
        let timeZoneContainer = UIView()
        timeZoneContainer.addSubview(timeZoneLabel)
        timeZoneLabel.autoPinEdgesToSuperviewEdges(with: .init(hMargin: Self.sectionMargin, vMargin: 0))
        stackView.addArrangedSubview(timeZoneContainer)

        let now = dateProvider()
        let defaultDate = Self.defaultDate(now: now, calendar: Calendar.current)
        datePicker.minimumDate = now
        datePicker.date = defaultDate
        timePicker.date = defaultDate

        updatePickerMode()
        pickerValueDidChange()
    }

    // MARK: Sheet height

    override func customSheetHeight() -> CGFloat {
        // Reserve room for the taller picker so the sheet's height stays
        // stable while the picker container animates between the two.
        let reservedPickerHeight = max(datePicker.bounds.height, timePicker.bounds.height)
        return super.customSheetHeight() + reservedPickerHeight - pickerContainer.bounds.height
    }

    // MARK: Selection

    @objc
    private func pickerValueDidChange() {
        datePill.configuration?.title = DateFormatter.localizedString(
            from: datePicker.date,
            dateStyle: .medium,
            timeStyle: .none,
        )
        timePill.configuration?.title = DateFormatter.localizedString(
            from: timePicker.date,
            dateStyle: .none,
            timeStyle: .short,
        )
        confirmButton.isEnabled = selectedDate > dateProvider()
    }

    private func updatePickerMode(animated: Bool = false) {
        switch pickerMode {
        case .date:
            setPill(datePill, isSelected: true)
            setPill(timePill, isSelected: false)
            timePickerHeightConstraint.isActive = false
            datePickerHeightConstraint.isActive = true
        case .time:
            setPill(datePill, isSelected: false)
            setPill(timePill, isSelected: true)
            datePickerHeightConstraint.isActive = false
            timePickerHeightConstraint.isActive = true
        }

        guard animated else {
            updatePickerVisibility()
            return
        }

        UIView.animate(
            withDuration: 0.4,
            delay: 0,
            usingSpringWithDamping: 0.8,
            initialSpringVelocity: 0,
            options: .curveEaseInOut,
            animations: {
                self.view.layoutIfNeeded()
            },
        )
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState],
            animations: {
                self.updatePickerVisibility()
            },
        )
    }

    private func updatePickerVisibility() {
        switch pickerMode {
        case .date:
            datePicker.alpha = 1
            timePicker.alpha = 0
            datePicker.accessibilityElementsHidden = false
            timePicker.accessibilityElementsHidden = true
        case .time:
            datePicker.alpha = 0
            timePicker.alpha = 1
            datePicker.accessibilityElementsHidden = true
            timePicker.accessibilityElementsHidden = false
        }
    }

    private func confirm() {
        let selectedDate = self.selectedDate
        guard selectedDate > dateProvider() else { return }
        dismiss(animated: true) { [didConfirm] in
            didConfirm(selectedDate)
        }
    }
}
