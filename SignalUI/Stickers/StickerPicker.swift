//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public enum StickerFavoriteChange {
    case added
    case removed
    case limitReached
}

public protocol StickerPickerContextMenuDelegate: AnyObject {
    func viewStickerPack(_ stickerPackInfo: StickerPackInfo)

    func stickerFavoriteDidChange(_ stickerInfo: StickerInfo, change: StickerFavoriteChange)

    func sendSticker(_ stickerMetadata: any StickerMetadata)

    func queueStickerPackForSending(_ stickerPackInfo: StickerPackInfo)
}

public protocol StoryStickerPickerDelegate: AnyObject {
    func didSelect(storySticker: EditorSticker.StorySticker)
}

public enum StoryStickerConfiguration {
    case hide
    case showWithDelegate(StoryStickerPickerDelegate)
}

public protocol StickerPickerDelegate: AnyObject {
    func didSelectSticker(_ stickerMetadata: any StickerMetadata)
}
