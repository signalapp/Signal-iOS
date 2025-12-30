//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

final class NewLinkedDeviceNotificationMegaphone: MegaphoneView {
    private let db: DB
    private let deviceStore: OWSDeviceStore

    init(
        db: DB,
        deviceStore: OWSDeviceStore,
        experienceUpgrade: ExperienceUpgrade,
        mostRecentlyLinkedDeviceDetails: MostRecentlyLinkedDeviceDetails,
    ) {
        self.db = db
        self.deviceStore = deviceStore
        super.init(experienceUpgrade: experienceUpgrade)

        imageName = "inactive-linked-device-reminder-megaphone"
        imageContentMode = .center
        titleText = OWSLocalizedString(
            "LINKED_DEVICE_NOTIFICATION_TITLE",
            comment: "Title for system notification when a new device is linked.",
        )

        let bodyText = String(
            format: OWSLocalizedString(
                "LINKED_DEVICE_NOTIFICATION_MEGAPHONE_BODY",
                comment: "Body for megaphone notification when a new device is linked. Embeds {{ time the device was linked }}",
            ),
            mostRecentlyLinkedDeviceDetails.linkedTime
                .formatted(date: .omitted, time: .shortened),
        )

        self.bodyText = bodyText

        let viewDeviceButton = Button(
            title: OWSLocalizedString(
                "NEW_LINKED_DEVICE_NOTIFICATION_MEGAPHONE_VIEW_DEVICE_BUTTON",
                value: "View device",
                comment: "Main button for megaphone notification when a new device is linked",
            ),
        ) { [weak self] in
            SignalApp.shared.showAppSettings(mode: .linkedDevices)
            self?.markAsViewed()
            self?.dismiss()
        }

        let acknowledgeButton = Button(
            title: CommonStrings.acknowledgeButton,
        ) { [weak self] in
            self?.markAsViewed()
            self?.dismiss()
        }

        setButtons(primary: acknowledgeButton, secondary: viewDeviceButton)
    }

    @MainActor
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func markAsViewed() {
        db.write { tx in
            deviceStore.clearMostRecentlyLinkedDeviceDetails(tx: tx)
        }
    }
}
