//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public typealias StyleIdType = Int

extension MessageBodyRanges {

    public enum SingleStyle: Int, Equatable, Hashable, Codable, CaseIterable {
        // Values kept in sync with Style option set
        case bold = 1
        case italic = 2
        case spoiler = 4
        case strikethrough = 8
        case monospace = 16

        public static func from(_ protoStyle: SSKProtoBodyRangeStyle) -> SingleStyle? {
            switch protoStyle {
            case .none:
                return nil
            case .bold:
                return .bold
            case .italic:
                return .italic
            case .spoiler:
                return .spoiler
            case .strikethrough:
                return .strikethrough
            case .monospace:
                return .monospace
            }
        }

        public var asProtoStyle: SSKProtoBodyRangeStyle {
            switch self {
            case .bold:
                return .bold
            case .italic:
                return .italic
            case .spoiler:
                return .spoiler
            case .strikethrough:
                return .strikethrough
            case .monospace:
                return .monospace
            }
        }

        public var asStyle: Style {
            return Style(rawValue: rawValue)
        }
    }

    public struct Style: OptionSet, Equatable, Hashable, Codable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let bold = Style(rawValue: SingleStyle.bold.rawValue)
        public static let italic = Style(rawValue: SingleStyle.italic.rawValue)
        public static let spoiler = Style(rawValue: SingleStyle.spoiler.rawValue)
        public static let strikethrough = Style(rawValue: SingleStyle.strikethrough.rawValue)
        public static let monospace = Style(rawValue: SingleStyle.monospace.rawValue)

        static let attributedStringKey = NSAttributedString.Key("OWSStyle")

        public func contains(style: SingleStyle) -> Bool {
            return self.contains(style.asStyle)
        }

        public mutating func insert(style: SingleStyle) {
            self.insert(style.asStyle)
        }

        public mutating func remove(style: SingleStyle) {
            self.remove(style.asStyle)
        }

        public var contents: [SingleStyle] {
            return SingleStyle.allCases.compactMap {
                return self.contains(style: $0) ? $0 : nil
            }
        }
    }

    /// Result of taking the styles as they appear in the original protos, and merging overlapping
    /// and adjacent instances of the same style
    public struct MergedSingleStyle: Equatable, Codable {
        public let style: SingleStyle
        public let mergedRange: NSRange
        public let id: StyleIdType

        internal init(style: SingleStyle, mergedRange: NSRange) {
            self.style = style
            self.mergedRange = mergedRange
            self.id = mergedRange.hashValue
        }

        internal static func merge(
            sortedOriginals: [NSRangedValue<SingleStyle>],
            mergeAdjacentRangesOfSameStyle: Bool = false
        ) -> [MergedSingleStyle] {
            var combined = [MergedSingleStyle]()
            var currentAccumulators = [SingleStyle: NSRange]()

            for style in sortedOriginals {

                var accumulator = currentAccumulators[style.value] ?? style.range
                defer { currentAccumulators[style.value] = accumulator }

                if accumulator.upperBound >= style.range.upperBound {
                    // interval is already inside accumulator
                    continue
                } else if accumulator.upperBound > style.range.lowerBound {
                    // interval hangs off the back end of accumulator
                    accumulator = NSRange(
                        location: accumulator.location,
                        length: style.range.upperBound - accumulator.location
                    )
                } else if mergeAdjacentRangesOfSameStyle, accumulator.upperBound == style.range.lowerBound {
                    // They are adjacent (but not overlapping)
                    accumulator = NSRange(
                        location: accumulator.location,
                        length: style.range.upperBound - accumulator.location
                    )
                } else if accumulator.upperBound <= style.range.lowerBound {
                    // interval does not overlap, we are now past it.
                    let mergedStyle = MergedSingleStyle(
                        style: style.value,
                        mergedRange: accumulator
                    )
                    combined.append(mergedStyle)
                    accumulator = style.range
                }
            }

            for (style, range) in currentAccumulators {
                let mergedStyle = MergedSingleStyle(
                    style: style,
                    mergedRange: range
                )
                combined.append(mergedStyle)
            }

            return combined.sorted(by: { $0.mergedRange.location < $1.mergedRange.location })
        }
    }

    /// Result of collapsing overlapping styles of different types.
    /// We still keep track of the original range each style came from (after merging overlaps
    /// of the same style)
    ///
    /// For example:
    /// 0   1   2   3   4   5   6   7   8   9
    /// [   bold   ]       [   spoiler    ]
    ///     [     italic      ]
    /// Would become 4 distinct collapsed ranges, but each
    /// would retain a reference to the original range of the single type:
    /// [bold] (0, 2) {bold: (0, 3)}
    /// [bold, italic] (2, 3)  {bold: (0, 3), italic: (2, 6)}
    /// [italic] (3, 5)  {italic: (2, 6)}
    /// [italic, spoiler] (5, 6){italic: (2, 6), spoiler: (5, 9)}
    /// [spoiler] (6, 9) {spoiler: (5, 9)}
    public struct CollapsedStyle: Equatable, Codable {
        public private(set) var style: Style
        public private(set) var originals: [SingleStyle: MergedSingleStyle]

        internal init(style: Style, originals: [SingleStyle: MergedSingleStyle]) {
            self.style = style
            self.originals = originals
        }

        internal static func empty() -> CollapsedStyle {
            return CollapsedStyle(style: [], originals: [:])
        }

        public var isEmpty: Bool { style.isEmpty }

        mutating func insert(_ mergedStyle: MergedSingleStyle) {
            if style.contains(style: mergedStyle.style) {
                owsFailDebug("Multiple styles of the same type should already be merged")
            }
            style.insert(style: mergedStyle.style)
            originals[mergedStyle.style] = mergedStyle
        }

        mutating func remove(_ style: SingleStyle) {
            self.style.remove(style: style)
            originals[style] = nil
        }

        public static func flatten(_ collapsedStyles: [NSRangedValue<CollapsedStyle>]) -> [NSRangedValue<SingleStyle>] {
            var coveredIds = Set<StyleIdType>()
            return collapsedStyles.flatMap { collapsedStyle in
                return collapsedStyle.value.originals.compactMap { original in
                    guard !coveredIds.contains(original.value.id) else {
                        return nil
                    }
                    return NSRangedValue(original.value.style, range: original.value.mergedRange)
                }
            }
        }
    }
}
