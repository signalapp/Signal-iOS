//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public protocol StoryStickerPickerDelegate: AnyObject {
    func didSelect(storySticker: EditorSticker.StorySticker)
}

public enum StoryStickerConfiguration {
    case hide
    case showWithDelegate(StoryStickerPickerDelegate)
}

public protocol StickerPickerDelegate: AnyObject {
    func didSelectSticker(_ stickerInfo: StickerInfo)
}
