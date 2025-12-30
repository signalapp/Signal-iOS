//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

class DisappearingMessagesCustomTimePickerViewController: HostingController<DisappearingMessagesCustomTimePickerView> {
    private let initialDurationSeconds: UInt32?
    private let completion: (_ selectedDurationSeconds: UInt32) -> Void

    private let viewModel: DisappearingMessagesCustomTimePickerViewModel

    init(
        initialDurationSeconds: UInt32?,
        completion: @escaping (_ selectedDurationSeconds: UInt32) -> Void,
    ) {
        self.initialDurationSeconds = initialDurationSeconds
        self.completion = completion

        self.viewModel = DisappearingMessagesCustomTimePickerViewModel(
            initialDurationSeconds: initialDurationSeconds,
        )

        super.init(wrappedView: DisappearingMessagesCustomTimePickerView(viewModel: viewModel))

        title = OWSLocalizedString(
            "DISAPPEARING_MESSAGES",
            comment: "table cell label in conversation settings",
        )

        viewModel.actionsDelegate = self
    }

    private var hasUnsavedChanges: Bool {
        return initialDurationSeconds != viewModel.selectedDurationSeconds
    }

    // Don't allow interactive dismiss when there are unsaved changes.
    override var isModalInPresentation: Bool {
        get { hasUnsavedChanges }
        set {}
    }

    private func updateNavigationItem() {
        if hasUnsavedChanges {
            navigationItem.rightBarButtonItem = .button(
                title: CommonStrings.setButton,
                style: .done,
                action: { [weak self] in
                    self?.completeAndPop()
                },
            )
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    private func completeAndPop() {
        completion(viewModel.selectedDurationSeconds)

        guard let navigationController else {
            owsFailDebug("Missing navigation controller!")
            return
        }

        navigationController.popViewController(animated: true)
    }
}

// MARK: - DisappearingMessagesCustomTimePickerViewModel.ActionsDelegate

extension DisappearingMessagesCustomTimePickerViewController: DisappearingMessagesCustomTimePickerViewModel.ActionsDelegate {
    fileprivate func updateForSelection(selectedDurationSeconds: UInt32) {
        updateNavigationItem()
    }
}

// MARK: -

private class DisappearingMessagesCustomTimePickerViewModel: ObservableObject {
    protocol ActionsDelegate: AnyObject {
        func updateForSelection(selectedDurationSeconds: UInt32)
    }

    enum Unit: CaseIterable {
        case seconds
        case minutes
        case hours
        case days
        case weeks

        var unitDurationSeconds: UInt32 {
            switch self {
            case .seconds: UInt32(TimeInterval.second)
            case .minutes: UInt32(TimeInterval.minute)
            case .hours: UInt32(TimeInterval.hour)
            case .days: UInt32(TimeInterval.day)
            case .weeks: UInt32(TimeInterval.week)
            }
        }

        var allowedValues: ClosedRange<UInt32> {
            switch self {
            case .seconds: 1...59
            case .minutes: 1...59
            case .hours: 1...23
            case .days: 1...6
            case .weeks: 1...4
            }
        }
    }

    weak var actionsDelegate: ActionsDelegate?

    @Published var selectedUnit: Unit
    @Published var selectedValue: UInt32

    var selectedDurationSeconds: UInt32 {
        selectedUnit.unitDurationSeconds * selectedValue
    }

    convenience init(initialDurationSeconds: UInt32?) {
        guard let initialDurationSeconds else {
            self.init(minUnit: ())
            return
        }

        let maxUnit = Unit.allCases.last!
        let maxUnitAllowedValue = maxUnit.allowedValues.upperBound
        let maxAllowedDurationSeconds = maxUnit.unitDurationSeconds * maxUnitAllowedValue
        if initialDurationSeconds > maxAllowedDurationSeconds {
            // Bugs (and poorly-behaved clients) could let us set a duration
            // greater than what the picker should allow. If we find one of
            // these durations, set to the max.
            self.init(selectedUnit: maxUnit, selectedValue: maxUnitAllowedValue)
            return
        }

        for unit in Unit.allCases {
            let quotient = initialDurationSeconds / unit.unitDurationSeconds
            let remainder = initialDurationSeconds % unit.unitDurationSeconds

            // If it divides cleanly into an allowed value, pick this unit.
            if remainder == 0, unit.allowedValues.contains(quotient) {
                self.init(selectedUnit: unit, selectedValue: quotient)
                return
            }
        }

        // The duration isn't unit-aligned, so we don't know what to choose.
        // Start with the lowest.
        self.init(minUnit: ())
    }

    private convenience init(minUnit: Void) {
        let minUnit = Unit.allCases.first!
        self.init(
            selectedUnit: minUnit,
            selectedValue: minUnit.allowedValues.lowerBound,
        )
    }

    private init(selectedUnit: Unit, selectedValue: UInt32) {
        self.selectedUnit = selectedUnit
        self.selectedValue = selectedValue
    }

    func setNewSelection(
        newSelectedUnit: Unit?,
        newSelectedValue: UInt32?,
    ) {
        selectedUnit = newSelectedUnit ?? selectedUnit
        selectedValue = newSelectedValue ?? selectedValue

        // Clamp to the max value allowed by the unit. This is important because
        // the unit can change, and the value-Picker will show a clamped value
        // because its set of possible values is constrained, but the actual
        // value property will not be clamped automatically.
        let maxAllowedValue = selectedUnit.allowedValues.upperBound
        if selectedValue > maxAllowedValue {
            selectedValue = maxAllowedValue
        }

        actionsDelegate?.updateForSelection(
            selectedDurationSeconds: selectedDurationSeconds,
        )
    }
}

struct DisappearingMessagesCustomTimePickerView: View {
    private typealias Unit = DisappearingMessagesCustomTimePickerViewModel.Unit

    @ObservedObject private var viewModel: DisappearingMessagesCustomTimePickerViewModel

    fileprivate init(viewModel: DisappearingMessagesCustomTimePickerViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        SignalList {
            HStack {
                Picker(
                    OWSLocalizedString(
                        "DISAPPEARING_MESSAGES_CUSTOM_TIME_VALUE_PICKER",
                        comment: "Title for a picker for the amount of time, in a given unit, to use for disappearing messages.",
                    ),
                    selection: Binding(
                        get: { viewModel.selectedValue },
                        set: { viewModel.setNewSelection(newSelectedUnit: nil, newSelectedValue: $0) },
                    ),
                ) {
                    ForEach(viewModel.selectedUnit.allowedValues, id: \.self) { val in
                        Text("\(val)")
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)

                Picker(
                    OWSLocalizedString(
                        "DISAPPEARING_MESSAGES_CUSTOM_TIME_UNIT_PICKER",
                        comment: "Title for a picker for the unit of time to use for disappearing messages.",
                    ),
                    selection: Binding(
                        get: { viewModel.selectedUnit },
                        set: { viewModel.setNewSelection(newSelectedUnit: $0, newSelectedValue: nil) },
                    ),
                ) {
                    ForEach(Unit.allCases, id: \.self) { unit in
                        let localizedString = switch unit {
                        case .seconds: OWSLocalizedString(
                                "DISAPPEARING_MESSAGES_SECONDS",
                                comment: "The unit for a number of seconds",
                            )
                        case .minutes: OWSLocalizedString(
                                "DISAPPEARING_MESSAGES_MINUTES",
                                comment: "The unit for a number of minutes",
                            )
                        case .hours: OWSLocalizedString(
                                "DISAPPEARING_MESSAGES_HOURS",
                                comment: "The unit for a number of hours",
                            )
                        case .days: OWSLocalizedString(
                                "DISAPPEARING_MESSAGES_DAYS",
                                comment: "The unit for a number of days",
                            )
                        case .weeks: OWSLocalizedString(
                                "DISAPPEARING_MESSAGES_WEEKS",
                                comment: "The unit for a number of weeks",
                            )
                        }

                        Text(localizedString)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: -

#if DEBUG

private extension DisappearingMessagesCustomTimePickerViewModel {
    static func forPreview() -> DisappearingMessagesCustomTimePickerViewModel {
        class PreviewActionsDelegate: ActionsDelegate {
            func updateForSelection(selectedDurationSeconds: UInt32) {
                print("selectedDurationSeconds: \(selectedDurationSeconds)")
            }
        }

        let viewModel = DisappearingMessagesCustomTimePickerViewModel(initialDurationSeconds: 180)
        let actionsDelegate = PreviewActionsDelegate()
        ObjectRetainer.retainObject(actionsDelegate, forLifetimeOf: viewModel)
        viewModel.actionsDelegate = actionsDelegate

        return viewModel
    }
}

#Preview {
    DisappearingMessagesCustomTimePickerView(viewModel: .forPreview())
}

#endif
