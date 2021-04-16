//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
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
        UIFont.ows_dynamicTypeBodyClamped.ows_semibold
    }

    private static let buttonVMargin: CGFloat = 5

    static var buttonHeight: CGFloat {
        max(48, buttonFont.lineHeight + buttonVMargin * 2)
    }
}
