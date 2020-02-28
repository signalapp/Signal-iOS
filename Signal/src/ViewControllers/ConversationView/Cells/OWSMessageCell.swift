//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
extension OWSMessageCell {
    class func cellReuseIdentifier(forMessageCellType cellType: OWSMessageCellType, isOutgoingMessage: Bool) -> String {
        // We use dashes instead of underscores as separators here since `OWSMessageCellType`
        // stringValue contains underscores.
        return "OWSMessageCell-\(cellType.stringValue)-\(isOutgoingMessage ?  "Outgoing" : "Incoming")"
    }

    class var allCellReuseIdentifiers: [String] {
        var reuseIdentifiers = [String]()
        for type in OWSMessageCellType.allCases {
            reuseIdentifiers.append(cellReuseIdentifier(forMessageCellType: type, isOutgoingMessage: true))
            reuseIdentifiers.append(cellReuseIdentifier(forMessageCellType: type, isOutgoingMessage: false))
        }
        return reuseIdentifiers
    }
}

extension OWSMessageCellType: CaseIterable {
    public static var allCases: [OWSMessageCellType] {
        [
            .unknown,
            .textOnlyMessage,
            .audio,
            .genericAttachment,
            .contactShare,
            .mediaMessage,
            .oversizeTextDownloading,
            .stickerMessage,
            .viewOnce
        ]
    }

    var stringValue: String { NSStringForOWSMessageCellType(self) }
    init(stringValue: String) {
        switch stringValue {
        case "OWSMessageCellType_Unknown":
            self = .unknown
        case "OWSMessageCellType_TextOnlyMessage":
            self = .textOnlyMessage
        case "OWSMessageCellType_Audio":
            self = .audio
        case "OWSMessageCellType_GenericAttachment":
            self = .genericAttachment
        case "OWSMessageCellType_ContactShare":
            self = .contactShare
        case "OWSMessageCellType_MediaMessage":
            self = .mediaMessage
        case "OWSMessageCellType_OversizeTextDownloading":
            self = .oversizeTextDownloading
        case "OWSMessageCellType_StickerMessage":
            self = .stickerMessage
        case "OWSMessageCellType_ViewOnce":
            self = .viewOnce
        default:
            owsFailDebug("unexpected message cell type")
            self = .unknown
        }
    }
}
