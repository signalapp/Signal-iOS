//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class CVMessageActionButton: CVLabel {
    let action: CVMessageAction

    required init(action: CVMessageAction) {
        self.action = action

        super.init(frame: .zero)

        configure()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        layoutMargins = .zero

        text = action.title
        font = Self.buttonFont
        textColor = (action.action == .none
                        ? Theme.secondaryTextAndIconColor
                        : Theme.conversationButtonTextColor)
        textAlignment = .center
    }

    private static var buttonFont: UIFont {
        UIFont.ows_dynamicTypeBody2Clamped.ows_semibold
    }

    private static let buttonVMargin: CGFloat = 5

    static var buttonHeight: CGFloat {
        max(44, ceil(buttonFont.lineHeight + buttonVMargin * 2))
    }
}
