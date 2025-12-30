//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Photos
import SignalServiceKit
import SignalUI

class LimitedPhotoPermissionsView: UIView {
    private let button: UIButton = {
        let selectMoreAction = UIAction(
            title: OWSLocalizedString(
                "ATTACHMENT_KEYBOARD_CONTEXT_MENU_BUTTON_SELECT_MORE",
                comment: "Button in a context menu from the 'manage' button in attachment panel that allows to select more photos/videos to give Signal access to",
            ),
            image: UIImage(named: "album-tilt-light"),
        ) { _ in
            guard let frontmostVC = CurrentAppContext().frontmostViewController() else { return }
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: frontmostVC)
        }
        let settingsAction = UIAction(
            title: OWSLocalizedString(
                "ATTACHMENT_KEYBOARD_CONTEXT_MENU_BUTTON_SYSTEM_SETTINGS",
                comment: "Button in a context menu from the 'manage' button in attachment panel that opens the iOS system settings for Signal to update access permissions",
            ),
            image: UIImage(named: "settings-light"),
        ) { _ in
            CurrentAppContext().openSystemSettings()
        }

        let button = UIButton(configuration: .smallSecondary(title: OWSLocalizedString(
            "ATTACHMENT_KEYBOARD_BUTTON_MANAGE",
            comment: "Button in chat attachment panel that allows to select photos/videos Signal has access to.",
        )))
        button.menu = UIMenu(children: [settingsAction, selectMoreAction])
        button.showsMenuAsPrimaryAction = true

        return button
    }()

    init() {
        super.init(frame: .zero)
        self.layoutMargins = .init(top: 0, leading: 20, bottom: 0, trailing: 15)

        let label = UILabel()
        label.textColor = UIColor.Signal.secondaryLabel
        label.font = .dynamicTypeSubheadlineClamped
        label.numberOfLines = 2
        label.setContentHuggingHorizontalLow()
        label.text = OWSLocalizedString(
            "ATTACHMENT_KEYBOARD_LIMITED_ACCESS",
            comment: "Text in chat attachment panel when Signal only has access to some photos/videos. This string is in a compact horizontal space, so it should be short if possible.",
        )

        button.setContentHuggingHigh()
        button.setCompressionResistanceHorizontalHigh()

        let stackView = UIStackView(arrangedSubviews: [label, button])
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center
        self.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
