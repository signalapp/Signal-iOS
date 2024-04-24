//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

final class InactiveLinkedDeviceReminderMegaphone: MegaphoneView {
    private var inactiveLinkedDeviceFinder: InactiveLinkedDeviceFinder {
        DependenciesBridge.shared.inactiveLinkedDeviceFinder
    }

    private let inactiveLinkedDevice: InactiveLinkedDevice

    /// The number of days until the linked device represented by this megaphone
    /// will expire. Clamps to a floor of one day.
    private var daysUntilExpiration: Int {
        let daysUntilExpiration: Int = DateUtil.daysFrom(
            firstDate: Date(),
            toSecondDate: inactiveLinkedDevice.expirationDate
        )

        // If there's less than 1 day till expiration, round up to one day.
        return max(daysUntilExpiration, 1)
    }

    init(
        inactiveLinkedDevice: InactiveLinkedDevice,
        fromViewController: UIViewController,
        experienceUpgrade: ExperienceUpgrade
    ) {
        self.inactiveLinkedDevice = inactiveLinkedDevice

        super.init(experienceUpgrade: experienceUpgrade)

        titleText = OWSLocalizedString(
            "INACTIVE_LINKED_DEVICE_REMINDER_MEGAPHONE_TITLE",
            comment: "Title for an in-app megaphone about a user's inactive linked device."
        )

        let bodyTextFormat = OWSLocalizedString(
            "INACTIVE_LINKED_DEVICE_REMINDER_MEGAPHONE_BODY_%d",
            tableName: "PluralAware",
            comment: "Title for an in-app megaphone about a user's inactive linked device. Embeds {{ %d: the number of days until that device's expiration; %2$@: the name of the device }}."
        )
        bodyText = String.localizedStringWithFormat(
            bodyTextFormat,
            daysUntilExpiration,
            inactiveLinkedDevice.displayName
        )

        imageName = "inactive-linked-device-reminder-megaphone"
        imageContentMode = .center

        let dontRemindMeButton = Button(title: OWSLocalizedString(
            "INACTIVE_LINKED_DEVICE_REMINDER_MEGAPHONE_DONT_REMIND_ME_BUTTON",
            comment: "Title for a button in an in-app megaphone about a user's inactive linked device, indicating the user doesn't want to be reminded."
        )) {
            DependenciesBridge.shared.db.asyncWrite(
                block: { tx in
                    self.inactiveLinkedDeviceFinder.permanentlyDisableFinders(tx: tx)
                },
                completionQueue: .main,
                completion: { [weak self] in
                    self?.dismiss()
                }
            )
        }
        let gotItButton = snoozeButton(
            fromViewController: fromViewController,
            snoozeTitle: OWSLocalizedString(
                "INACTIVE_LINKED_DEVICE_REMINDER_MEGAPHONE_GOT IT_BUTTON",
                comment: "Title for a button in an in-app megaphone about a user's inactive linked device, temporarily dismissing the megaphone."
            )
        )
        setButtons(primary: gotItButton, secondary: dontRemindMeButton)
    }

    @available(*, unavailable, message: "Use other constructor!")
    required init(coder: NSCoder) {
        owsFail("Use other constructor!")
    }
}
