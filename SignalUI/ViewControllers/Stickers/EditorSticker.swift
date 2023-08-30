//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalMessaging

private class LayerContainerView: UIView {
    let contentLayer: CALayer
    init(contentLayer: CALayer) {
        self.contentLayer = contentLayer
        super.init(frame: .zero)
        layer.addSublayer(contentLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentLayer.frame = CGRect(origin: self.frame.origin, size: self.frame.size)
    }
}

// MARK: - EditorSticker

public enum EditorSticker {
    case regular(StickerInfo)
    case story(StorySticker)

    // MARK: StorySticker

    public enum StorySticker {
        case clockDigital(DigitalClockStyle)
        case clockAnalog(AnalogClockStyle)

        func previewView() -> UIView {
            switch self {
            case .clockDigital(let digitalClockStyle):
                let label = UILabel()
                label.attributedText = digitalClockStyle.attributedString(date: Date())
                label.adjustsFontSizeToFitWidth = true
                return label
            case .clockAnalog(let clockStyle):
                let clockLayer = clockStyle.drawClock(date: Date())
                return LayerContainerView(contentLayer: clockLayer)
            }
        }

        /// A list of story sticker configurations to display in the sticker picker.
        ///
        /// Contains one of each story sticker with each one's default configuration.
        static var pickerStickers: [StorySticker] {
            [
                .clockDigital(.white),
                .clockAnalog(.arabic),
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

// MARK: AnalogClockStyle

extension EditorSticker.StorySticker {
    public enum AnalogClockStyle: CaseIterable {
        case arabic
        case baton
        case explorer
        case diver

        var backgroundImage: UIImage {
            switch self {
            case .arabic:
                return #imageLiteral(resourceName: "clock-arabic.pdf")
            case .baton:
                return #imageLiteral(resourceName: "clock-baton.pdf")
            case .explorer:
                return #imageLiteral(resourceName: "clock-explorer.pdf")
            case .diver:
                return #imageLiteral(resourceName: "clock-diver.pdf")
            }
        }

        func drawClock(date: Date) -> CALayer {
            return AnalogClockLayer(style: self, date: date)
        }

        var hourHandImage: UIImage {
            switch self {
            case .arabic:
                return #imageLiteral(resourceName: "clock-arabic-hour.pdf")
            case .baton:
                return #imageLiteral(resourceName: "clock-baton-hour.pdf")
            case .explorer:
                return #imageLiteral(resourceName: "clock-explorer-hour.pdf")
            case .diver:
                return #imageLiteral(resourceName: "clock-diver-hour.pdf")
            }
        }

        var hourHandHeight: CGFloat {
            switch self {
            case .arabic:
                return 1/3
            case .baton:
                return 0.35
            case .explorer:
                return 149/600
            case .diver:
                return 139/600
            }
        }

        var hourHandOffset: CGFloat {
            switch self {
            case .arabic:
                return 0.72
            case .baton:
                return 16/21
            case .explorer:
                return 1
            case .diver:
                return 141/139
            }
        }

        var minuteHandImage: UIImage {
            switch self {
            case .arabic:
                return #imageLiteral(resourceName: "clock-arabic-minute.pdf")
            case .baton:
                return #imageLiteral(resourceName: "clock-baton-minute.pdf")
            case .explorer:
                return #imageLiteral(resourceName: "clock-explorer-minute.pdf")
            case .diver:
                return #imageLiteral(resourceName: "clock-diver-minute.pdf")
            }
        }

        var minuteHandHeight: CGFloat {
            switch self {
            case .arabic:
                return 280/600
            case .baton:
                return 308/600
            case .explorer:
                return 229/600
            case .diver:
                return 268/600
            }
        }

        var minuteHandOffset: CGFloat {
            switch self {
            case .arabic:
                return 4/5
            case .baton:
                return 129/154
            case .explorer:
                return 1
            case .diver:
                return 1
            }
        }

        var centerImage: UIImage? {
            switch self {
            case .diver:
                return #imageLiteral(resourceName: "clock-diver-center.pdf")
            case .arabic, .baton, .explorer:
                return nil
            }
        }

        func nextStyle() -> AnalogClockStyle {
            switch self {
            case .arabic:
                return .baton
            case .baton:
                return .explorer
            case .explorer:
                return .diver
            case .diver:
                return .arabic
            }
        }

        func stickerWithNextStyle() -> EditorSticker {
            return .story(.clockAnalog(self.nextStyle()))
        }
    }
}

// MARK: - AnalogClockLayer

private class AnalogClockLayer: CALayer {
    typealias Style = EditorSticker.StorySticker.AnalogClockStyle

    private let clockStyle: Style
    private let date: Date
    private let background: CALayer
    private let hourHand: CALayer
    private let minuteHand: CALayer
    private let center: CALayer?

    override var frame: CGRect {
        didSet {
            updateSublayerFrames()
        }
    }

    init(style: Style, date: Date) {
        self.clockStyle = style
        self.date = date

        background = UIImageView(image: style.backgroundImage).layer

        let hourHandImageView = UIImageView(image: style.hourHandImage)
        hourHandImageView.contentMode = .scaleAspectFit
        hourHand = hourHandImageView.layer

        let minuteHandImageView = UIImageView(image: style.minuteHandImage)
        minuteHandImageView.contentMode = .scaleAspectFit
        minuteHand = minuteHandImageView.layer

        center = style.centerImage.map(UIImageView.init(image:))?.layer

        super.init()
        addSublayer(background)
        addSublayer(hourHand)
        addSublayer(minuteHand)
        if let center {
            addSublayer(center)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateSublayerFrames() {
        let dateComponents = Calendar.current.dateComponents([.hour, .minute], from: date)
        let minutes = CGFloat(dateComponents.minute ?? 0)
        let hours = CGFloat(dateComponents.hour ?? 0) + minutes/60
//        let minutes = CGFloat.random(in: 0..<60)
//        let hours = CGFloat.random(in: 0..<12)

        background.frame.size = self.frame.size
        transfrom(
            clockHandLayer: hourHand,
            time: hours/12,
            height: clockStyle.hourHandHeight,
            offset: clockStyle.hourHandOffset
        )
        transfrom(
            clockHandLayer: minuteHand,
            time: minutes/60,
            height: clockStyle.minuteHandHeight,
            offset: clockStyle.minuteHandOffset
        )
        if let center {
            let size: CGFloat = 42/600 * self.frame.height
            center.frame = CGRect(
                origin: .init(
                    x: self.frame.width/2 - size/2,
                    y: self.frame.height/2 - size/2
                ),
                size: .square(size)
            )
        }
    }

    private func transfrom(
        clockHandLayer hand: CALayer,
        time: CGFloat,
        height: CGFloat,
        offset: CGFloat
    ) {
        hand.setAffineTransform(.identity)
        hand.frame.size.height = self.frame.height * height
        hand.frame.origin = .init(
            x: self.frame.width/2 - hand.frame.size.width/2,
            y: self.frame.height/2 - hand.frame.size.height/2
        )

        hand.anchorPoint = .init(x: 0.5, y: offset)
        hand.setAffineTransform(
            .init(translationX: 0, y: -hand.frame.height * (offset - 0.5))
            .rotated(by: time * 2 * .pi)
        )
    }

}
