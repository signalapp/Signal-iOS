//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public enum StickerToastStrings {

    public static var addedToFavorites: String {
        OWSLocalizedString(
            "STICKER_ADDED_TO_FAVORITES_TOAST",
            comment: "Text shown in a toast confirming a sticker was added to favorites",
        )
    }

    public static var removedFromFavorites: String {
        OWSLocalizedString(
            "STICKER_REMOVED_FROM_FAVORITES_TOAST",
            comment: "Text shown in a toast confirming a sticker was removed from favorites",
        )
    }

    public static var favoriteLimitReached: String {
        String.localizedStringWithFormat(
            OWSLocalizedString(
                "STICKER_FAVORITE_MAX_TOAST_%d",
                tableName: "PluralAware",
                comment: "Text shown in a toast when the user has reached the max sticker favorite count and cannot add more. Embeds {{ max number of favorite stickers }}",
            ),
            StickerManager.maxStickerFavorites,
        )
    }
}
