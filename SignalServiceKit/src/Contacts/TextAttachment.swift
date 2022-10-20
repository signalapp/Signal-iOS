//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct UnsentTextAttachment {
    public let text: String?
    public let textStyle: TextAttachment.TextStyle
    public let textForegroundColor: UIColor
    public let textBackgroundColor: UIColor?
    public let background: TextAttachment.Background

    public let linkPreviewDraft: OWSLinkPreviewDraft?

    public init(
        text: String?,
        textStyle: TextAttachment.TextStyle,
        textForegroundColor: UIColor,
        textBackgroundColor: UIColor?,
        background: TextAttachment.Background,
        linkPreviewDraft: OWSLinkPreviewDraft?
    ) {
        self.text = text
        self.textStyle = textStyle
        self.textForegroundColor = textForegroundColor
        self.textBackgroundColor = textBackgroundColor
        self.background = background
        self.linkPreviewDraft = linkPreviewDraft
    }

    public func validateLinkPreviewAndBuildTextAttachment(transaction: SDSAnyWriteTransaction) -> TextAttachment? {
        var validatedLinkPreview: OWSLinkPreview?
        if let linkPreview = linkPreviewDraft {
            do {
                validatedLinkPreview = try OWSLinkPreview.buildValidatedLinkPreview(fromInfo: linkPreview, transaction: transaction)
            } catch LinkPreviewError.featureDisabled {
                validatedLinkPreview = OWSLinkPreview(urlString: linkPreview.urlString, title: nil, imageAttachmentId: nil)
            } catch {
                Logger.error("Failed to generate link preview.")
            }
        }

        guard validatedLinkPreview != nil || !(text?.isEmpty ?? true) else {
            owsFailDebug("Empty content")
            return nil
        }
        return TextAttachment(
            text: text,
            textStyle: textStyle,
            textForegroundColor: textForegroundColor,
            textBackgroundColor: textBackgroundColor,
            background: background,
            linkPreview: validatedLinkPreview
        )
    }
}

public struct TextAttachment: Codable, Equatable {
    public let text: String?

    public enum TextStyle: Int, Codable, Equatable {
        case regular = 0
        case bold = 1
        case serif = 2
        case script = 3
        case condensed = 4
    }
    public let textStyle: TextStyle

    private let textForegroundColorHex: UInt32?
    public var textForegroundColor: UIColor? { textForegroundColorHex.map { UIColor(argbHex: $0) } }

    private let textBackgroundColorHex: UInt32?
    public var textBackgroundColor: UIColor? { textBackgroundColorHex.map { UIColor(argbHex: $0) } }

    private enum RawBackground: Codable, Equatable {
        case color(hex: UInt32)
        case gradient(raw: RawGradient)
        struct RawGradient: Codable, Equatable {
            let colors: [UInt32]
            let positions: [Float]
            let angle: UInt32

            init(colors: [UInt32], positions: [Float], angle: UInt32) {
                self.colors = colors
                self.positions = positions
                self.angle = angle
            }

            init(from decoder: Decoder) throws {
                let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
                self.colors = try container.decode([UInt32].self, forKey: .colors)
                self.positions = try container.decode([Float].self, forKey: .positions)
                self.angle = try container.decode(UInt32.self, forKey: .angle)
            }

            func buildProto() throws -> SSKProtoTextAttachmentGradient {
                let builder = SSKProtoTextAttachmentGradient.builder()
                if let startColor = colors.first {
                    builder.setStartColor(startColor)
                }
                if let endColor = colors.last {
                    builder.setEndColor(endColor)
                }
                builder.setColors(colors)
                builder.setPositions(positions)
                builder.setAngle(angle)
                return try builder.build()
            }
        }
    }
    private let rawBackground: RawBackground

    public enum Background {
        case color(UIColor)
        case gradient(Gradient)
        public struct Gradient {
            public init(colors: [UIColor], locations: [CGFloat], angle: UInt32) {
                self.colors = colors
                self.locations = locations
                self.angle = angle
            }
            public init(colors: [UIColor]) {
                let locations: [CGFloat] = colors.enumerated().map { element in
                    return CGFloat(element.offset) / CGFloat(colors.count - 1)
                }
                self.init(colors: colors, locations: locations, angle: 180)
            }
            public let colors: [UIColor]
            public let locations: [CGFloat]
            public let angle: UInt32
        }
    }
    public var background: Background {
        switch rawBackground {
        case .color(let hex):
            return .color(.init(argbHex: hex))
        case .gradient(let rawGradient):
            return .gradient(.init(
                colors: rawGradient.colors.map { UIColor(argbHex: $0) },
                locations: rawGradient.positions.map { CGFloat($0) },
                angle: rawGradient.angle
            ))
        }
    }

    public private(set) var preview: OWSLinkPreview?

    init(from proto: SSKProtoTextAttachment, transaction: SDSAnyWriteTransaction) throws {
        self.text = proto.text?.nilIfEmpty

        guard let style = proto.textStyle else {
            throw OWSAssertionError("Missing style for attachment.")
        }

        switch style {
        case .default, .regular:
            self.textStyle = .regular
        case .bold:
            self.textStyle = .bold
        case .serif:
            self.textStyle = .serif
        case .script:
            self.textStyle = .script
        case .condensed:
            self.textStyle = .condensed
        }

        if proto.hasTextForegroundColor {
            textForegroundColorHex = proto.textForegroundColor
        } else {
            textForegroundColorHex = nil
        }

        if proto.hasTextBackgroundColor {
            textBackgroundColorHex = proto.textBackgroundColor
        } else {
            textBackgroundColorHex = nil
        }

        if let gradient = proto.gradient {
            let colors: [UInt32]
            let positions: [Float]
            if !gradient.colors.isEmpty && !gradient.positions.isEmpty {
                colors = gradient.colors
                positions = gradient.positions
            } else {
                colors = [ gradient.startColor, gradient.endColor ]
                positions = [ 0, 1 ]
            }
            rawBackground = .gradient(raw: .init(
                colors: colors,
                positions: positions,
                angle: gradient.angle
            ))
        } else if proto.hasColor {
            rawBackground = .color(hex: proto.color)
        } else {
            throw OWSAssertionError("Missing background for attachment.")
        }

        if let preview = proto.preview {
            self.preview = try OWSLinkPreview.buildValidatedLinkPreview(proto: preview, transaction: transaction)
        }
    }

    public func buildProto(transaction: SDSAnyReadTransaction) throws -> SSKProtoTextAttachment {
        let builder = SSKProtoTextAttachment.builder()

        if let text = text {
            builder.setText(text)
        }

        let textStyle: SSKProtoTextAttachmentStyle = {
            switch self.textStyle {
            case .regular: return .regular
            case .bold: return .bold
            case .serif: return .serif
            case .script: return .script
            case .condensed: return .condensed
            }
        }()
        builder.setTextStyle(textStyle)

        if let textForegroundColorHex = textForegroundColorHex {
            builder.setTextForegroundColor(textForegroundColorHex)
        }

        if let textBackgroundColorHex = textBackgroundColorHex {
            builder.setTextBackgroundColor(textBackgroundColorHex)
        }

        switch rawBackground {
        case .color(let hex):
            builder.setColor(hex)
        case .gradient(let raw):
            builder.setGradient(try raw.buildProto())
        }

        if let preview = preview {
            builder.setPreview(try preview.buildProto(transaction: transaction))
        }

        return try builder.build()
    }

    public init(
        text: String?,
        textStyle: TextStyle,
        textForegroundColor: UIColor,
        textBackgroundColor: UIColor?,
        background: Background,
        linkPreview: OWSLinkPreview?
    ) {
        self.text = text
        self.textStyle = textStyle
        self.textForegroundColorHex = textForegroundColor.argbHex
        self.textBackgroundColorHex = textBackgroundColor?.argbHex
        self.rawBackground = {
            switch background {
            case .color(let color):
                return .color(hex: color.argbHex)

            case .gradient(let gradient):
                return .gradient(raw: .init(colors: gradient.colors.map { $0.argbHex },
                                            positions: gradient.locations.map { Float($0) },
                                            angle: gradient.angle))
            }
        }()
        self.preview = linkPreview
    }

    /// Attempts to create a draft from the final version, so that it can be re-sent with new independent link attachment
    /// objects created. If link recreation from url fails, will omit the link.
    public func asUnsentAttachment() -> UnsentTextAttachment {
        var linkPreviewDraft: OWSLinkPreviewDraft?
        if
            let preview = preview,
            let urlString = preview.urlString,
            let url = URL(string: urlString)
        {
            linkPreviewDraft = OWSLinkPreviewDraft(url: url, title: preview.title)
        }
        return UnsentTextAttachment(
            text: text,
            textStyle: textStyle,
            textForegroundColor: textForegroundColor ?? .white,
            textBackgroundColor: textBackgroundColor,
            background: background,
            linkPreviewDraft: linkPreviewDraft
        )
    }
}
