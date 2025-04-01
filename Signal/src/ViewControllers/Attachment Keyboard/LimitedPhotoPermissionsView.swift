//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI
import SignalServiceKit
import Photos

class LimitedPhotoPermissionsView: UIView {
    private let button: UIButton = {
        let selectMoreAction = UIAction(
            title: OWSLocalizedString(
                "ATTACHMENT_KEYBOARD_CONTEXT_MENU_BUTTON_SELECT_MORE",
                comment: "Button in a context menu from the 'manage' button in attachment panel that allows to select more photos/videos to give Signal access to"
            ),
            image: UIImage(named: "album-tilt-light")
        ) { _ in
            guard let frontmostVC = CurrentAppContext().frontmostViewController() else { return }
            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: frontmostVC)
        }
        let settingsAction = UIAction(
            title: OWSLocalizedString(
                "ATTACHMENT_KEYBOARD_CONTEXT_MENU_BUTTON_SYSTEM_SETTINGS",
                comment: "Button in a context menu from the 'manage' button in attachment panel that opens the iOS system settings for Signal to update access permissions"
            ),
            image: UIImage(named: "settings-light")
        ) { _ in
            let openSettingsURL = URL(string: UIApplication.openSettingsURLString)!
            UIApplication.shared.open(openSettingsURL)
        }

        var buttonConfig = UIButton.Configuration.gray()
        buttonConfig.cornerStyle = .capsule
        buttonConfig.baseForegroundColor = UIColor.Signal.label
        buttonConfig.baseBackgroundColor = UIColor.Signal.tertiaryFill
        var titleAttributedString = AttributedString(
            OWSLocalizedString(
                "ATTACHMENT_KEYBOARD_BUTTON_MANAGE",
                comment: "Button in chat attachment panel that allows to select photos/videos Signal has access to."
            )
        )
        titleAttributedString.font = UIFont.dynamicTypeFootnoteClamped.medium()
        buttonConfig.attributedTitle = titleAttributedString

        let button = UIButton(configuration: buttonConfig)
        button.menu = UIMenu(children: [selectMoreAction, settingsAction])
        button.showsMenuAsPrimaryAction = true
        button.titleLabel?.font = .dynamicTypeFootnoteClamped

        return button
    }()

    init() {
        super.init(frame: .zero)
        self.layoutMargins = .init(top: 0, leading: 20, bottom: 0, trailing: 15)

        let label = UILabel()
        label.textColor = UIColor.Signal.secondaryLabel
        label.font = .dynamicTypeBody2Clamped
        label.text = OWSLocalizedString(
            "ATTACHMENT_KEYBOARD_LIMITED_ACCESS",
            comment: "Text in chat attachment panel when Signal only has access to some photos/videos. This string is in a compact horizontal space, so it should be short if possible."
        )

        addSubview(label)
        label.autoPinEdges(toSuperviewMarginsExcludingEdge: .trailing)
        label.setContentHuggingLow()
        addSubview(button)
        button.autoPinEdges(toSuperviewMarginsExcludingEdge: .leading)
        button.autoPinEdge(.leading, to: .trailing, of: label, withOffset: 8)
        button.setContentHuggingHigh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
