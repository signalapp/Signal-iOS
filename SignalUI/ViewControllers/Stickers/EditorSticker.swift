//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalMessaging

// MARK: - EditorSticker

public enum EditorSticker {
    case regular(StickerInfo)
    case story(StorySticker)

    // MARK: StorySticker

    public enum StorySticker {
        case clockDigital(DigitalClockStyle)

        func previewView() -> UIView {
            switch self {
            case .clockDigital(let digitalClockStyle):
                let label = UILabel()
                label.attributedText = digitalClockStyle.attributedString(date: Date())
                label.adjustsFontSizeToFitWidth = true
                return label
            }
        }

        /// A list of story sticker configurations to display in the sticker picker.
        ///
        /// Contains one of each story sticker with each one's default configuration.
        static var pickerStickers: [StorySticker] {
            [
                .clockDigital(.white),
            ]
        }
    }
}

// MARK: DigitalClockStyle

extension EditorSticker.StorySticker {
    public enum DigitalClockStyle: CaseIterable {
        case white
        case black
        case light
        case dark
        case amber

        private var foregroundColor: UIColor {
            switch self {
            case .white, .light, .dark:
                return .ows_white
            case .black:
                return .ows_black
            case .amber:
                return .init(rgbHex: 0xFF7629)
            }
        }

        var backgroundColor: UIColor? {
            switch self {
            case .white, .black:
                return nil
            case .light:
                return .ows_whiteAlpha40
            case .dark:
                return .ows_blackAlpha40
            case .amber:
                return .ows_blackAlpha60
            }
        }

        func attributedString(
            date: Date,
            scaleFactor: CGFloat = 1.0
        ) -> NSAttributedString {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm"
            let timeString = timeFormatter.string(from: date)
            let timeFont = UIFont.digitalClockFont(withPointSize: 96 * scaleFactor)
            let timeAttributedString = NSAttributedString(
                string: timeString,
                attributes: [
                    .font: timeFont,
                    .foregroundColor: self.foregroundColor,
                ]
            )

            let amPMFormatter = DateFormatter()
            amPMFormatter.dateFormat = " a"
            let amPMString = amPMFormatter.string(from: date)
            let amPMFont = UIFont.regularFont(ofSize: 24 * scaleFactor)
            let amPMAttributedString = NSAttributedString(
                string: amPMString,
                attributes: [
                    .font: amPMFont,
                    .foregroundColor: self.foregroundColor,
                ]
            )

            return timeAttributedString + amPMAttributedString
        }

        func nextStyle() -> DigitalClockStyle {
            switch self {
            case .white:
                return .black
            case .black:
                return .light
            case .light:
                return .dark
            case .dark:
                return .amber
            case .amber:
                return .white
            }
        }

        func stickerWithNextStyle() -> EditorSticker {
            return .story(.clockDigital(self.nextStyle()))
        }
    }
}
