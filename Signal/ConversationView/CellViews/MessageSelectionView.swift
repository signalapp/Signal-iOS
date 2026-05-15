//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

/// ManualLayoutView wrapper around SelectionIndicatorView.
class MessageSelectionView: ManualLayoutView {

    private let selectionIndicatorView = SelectionIndicatorView(style: .list)

    var isSelected: Bool {
        get {
            selectionIndicatorView.isSelected
        }
        set {
            selectionIndicatorView.isSelected = newValue
        }
    }

    init() {
        super.init(name: "MessageSelectionView")

        addSubviewToFillSuperviewEdges(selectionIndicatorView)
    }

    static var preferredSize: CGSize {
        CGSize(square: SelectionIndicatorView.preferredSize)
    }

    func updateStyle(conversationStyle: ConversationStyle) {
        selectionIndicatorView.fillColor = conversationStyle.chatColorValue.asChatUIElementTintColor()
        // Less transparent empty circle when there's a wallpaper and we're in light theme
        // to improve legibility over darker wallpapers.
        if
            conversationStyle.isDarkThemeEnabled == false,
            conversationStyle.hasWallpaper
        {
            selectionIndicatorView.unselectedListIndicatorColor = UIColor(rgbHex: 0x808080, alpha: 0.5)
        } else {
            selectionIndicatorView.unselectedListIndicatorColor = nil // reset to default
        }
    }
}
