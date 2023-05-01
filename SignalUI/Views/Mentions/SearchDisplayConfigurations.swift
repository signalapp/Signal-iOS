//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension HydratedMessageBody.DisplayConfiguration.SearchRanges {

    public static func matchedRanges(_ ranges: [NSRange]) -> Self {
        return HydratedMessageBody.DisplayConfiguration.SearchRanges(
            matchingBackgroundColor: .fixed(ConversationStyle.searchMatchHighlightColor),
            matchingForegroundColor: .fixed(.ows_black),
            matchedRanges: ranges
        )
    }
}
