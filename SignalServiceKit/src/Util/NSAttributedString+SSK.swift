//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Represents an argument passed when creating an attributed string using
/// formatting, where attributes may be applied to the substituted value of the
/// argument in the formatted string.
public enum AttributedFormatArg {
    public typealias Attributes = [NSAttributedString.Key: Any]

    /// Substitute the argument as-is, without applying attributes.
    case raw(_ value: CVarArg)

    /// Substitute the string and apply the given attributes.
    case string(_ string: String, attributes: Attributes)

    fileprivate var fallback: CVarArg {
        switch self {
        case let .raw(value):
            return value
        case let .string(value, _):
            return value
        }
    }
}

public extension NSAttributedString {
    /// The challenge here is: given a format string, which may be of either
    /// Localizable.strings format or PluralAware.stringsdict format (see below
    /// for examples), and a set of arguments that will be substituted into the
    /// format string, apply attributes specific to each argument to the range
    /// in the formatted string that will contain the substituted argument.
    ///
    /// For strings from `Localizable.strings` files, the format arg placeholders
    /// are well-known and consistent: `%@` for a single-argument format string,
    /// and `%<arg-number>$@` for a multiple-argument format string. For strings
    /// from `PluralAware.stringsdict` files there is another layer of
    /// indirection: the format string is assembled by the system in response to
    /// the format arg indicating the degree of the plural-aware string (e.g.,
    /// "zero, one, or more"), and the full format string (w/o substitutions) is
    /// not available to us. Consequently, we must take an approach that is
    /// agnostic to the format string, and instead leverages a fully-formatted
    /// string.
    ///
    /// The approach taken here uses placeholders. We substitute into the format
    /// string, but for each argument we want to substitute we will instead
    /// substitute a "placeholder" UUID string we associate with the arg. We
    /// then search for those UUIDs in the formatted string, and assemble a new
    /// string in which each UUID is replaced with the argument for which it is
    /// placeholding. While replacing, we track the ranges of the args and use
    /// them to associate that arg's attributes.
    ///
    /// This approach allows us to avoid collisions between the substituted
    /// arguments either with each other or the text of the format string. It
    /// is also agnostic to properties such as RTL, or if the format string or
    /// arguments contain Unicode.
    ///
    /// - Parameter fromFormat: the format string to substitute into.
    /// - Parameter attributedFormatArgs: format args, with their respective attributes.
    /// - Parameter defaultAttributes: attributes to apply to portions of the string without substitutions.
    static func make(
        fromFormat format: String,
        attributedFormatArgs formatArgs: [AttributedFormatArg],
        defaultAttributes: AttributedFormatArg.Attributes = [:]
    ) -> NSAttributedString {
        do {
            // Confirm format string does not contain Unicode isolates, since
            // we'll be adding those ourselves later.

            guard !format.contains(where: { c in
                c == .unicodeFirstStrongIsolate || c == .unicodePopDirectionalIsolate
            }) else {
                throw OWSAssertionError("Format string contained unicode isolates!")
            }

            // Format the string, and get the placeholders in string order

            let (formattedCopyWithPlaceholders, placeholdersInStringOrder) = try formatWithPlaceholders(
                format: format,
                formatArgs: formatArgs
            )

            // Build an attributed string from the formatted string, replacing
            // the placeholder values with substitutions attributed with their
            // corresponding attributes.

            let formattedCopyWithAttributes = NSMutableAttributedString()

            var nextChunkStartIndex = formattedCopyWithPlaceholders.startIndex
            for (placeholder, range) in placeholdersInStringOrder {
                // Grab the chunk of the string up to the start of this placeholder...
                let chunkUpToPlaceholder = formattedCopyWithPlaceholders[nextChunkStartIndex..<range.lowerBound]
                formattedCopyWithAttributes.append(
                    String(chunkUpToPlaceholder),
                    attributes: defaultAttributes
                )

                // ...and mark that the next chunk starts at the end of this placeholder.
                nextChunkStartIndex = range.upperBound

                // Add the substitution and attribute it. Always wrap the
                // substitution in Unicode isolates, to avoid any potential
                // RTL/LTR formatting issues.
                formattedCopyWithAttributes.append(
                    "\(Character.unicodeFirstStrongIsolate)\(placeholder.substitutionToApply)\(Character.unicodePopDirectionalIsolate)",
                    attributes: placeholder.attributesToApply
                )
            }

            let chunkAfterFinalPlaceholder = String(formattedCopyWithPlaceholders[nextChunkStartIndex..<formattedCopyWithPlaceholders.endIndex])
            formattedCopyWithAttributes.append(
                chunkAfterFinalPlaceholder,
                attributes: defaultAttributes
            )

            return formattedCopyWithAttributes
        } catch let error {
            // OWSAssertionError has internal logging logic
            if !(error is OWSAssertionError) {
                owsFailDebug("Error: \(error)")
            }

            Logger.warn("Returning unattributed string.")

            // If we failed to add the attributes for whatever reason, return
            // an unattributed version.

            let formattedString = String(
                format: format,
                locale: NSLocale.current,
                arguments: formatArgs.map { $0.fallback }
            )

            return NSAttributedString(string: formattedString, attributes: defaultAttributes)
        }
    }

    private struct FormatArgPlaceholder {
        let value: String = UUID().uuidString
        let substitutionToApply: CVarArg
        let attributesToApply: AttributedFormatArg.Attributes
    }

    private static func formatWithPlaceholders(
        format: String,
        formatArgs: [AttributedFormatArg]
    ) throws -> (
        formattedCopyWithPlaceholders: String,
        placeholdersInStringOrder: [(placeholder: FormatArgPlaceholder, range: Range<String.Index>)]
    ) {
        var placeholders = [FormatArgPlaceholder]()
        let formattedCopyWithPlaceholders = String(
            format: format,
            locale: Locale.current,
            arguments: formatArgs.map { arg -> CVarArg in
                switch arg {
                case let .raw(value):
                    return value
                case let .string(value, attributes):
                    let placeholder = FormatArgPlaceholder(
                        substitutionToApply: value,
                        attributesToApply: attributes
                    )

                    placeholders.append(placeholder)
                    return placeholder.value
                }
            }
        )

        // Find the ranges of the placeholder values, in order

        let placeholdersInStringOrder = try placeholders
            .map { placeholder throws -> (placeholder: FormatArgPlaceholder, range: Range<String.Index>) in
                guard var range = formattedCopyWithPlaceholders.range(of: placeholder.value) else {
                    throw OWSAssertionError("Placeholder value unexpectedly missing from formatted copy")
                }

                // iOS may wrap the placeholder in Unicode isolates
                // automatically if it thinks it should per the locale,
                // format string, arg, etc. If it did, we want to include
                // the isolates in the placeholder range.
                if
                    range.lowerBound > formattedCopyWithPlaceholders.startIndex,
                    range.upperBound < formattedCopyWithPlaceholders.endIndex
                {
                    let prevIdx = formattedCopyWithPlaceholders.index(before: range.lowerBound)
                    let prevChar = formattedCopyWithPlaceholders[prevIdx]

                    // Because ranges are exclusive of the upper bound, the
                    // "next" char is at the upper bound. This is safe since
                    // we checked against `.endIndex` above.
                    let nextChar = formattedCopyWithPlaceholders[range.upperBound]

                    if
                        prevChar == Character.unicodeFirstStrongIsolate,
                        nextChar == Character.unicodePopDirectionalIsolate
                    {
                        range = prevIdx..<formattedCopyWithPlaceholders.index(after: range.upperBound)
                    }
                }

                return (placeholder: placeholder, range: range)
            }.sorted {
                $0.range.lowerBound < $1.range.lowerBound
            }

        return (
            formattedCopyWithPlaceholders: formattedCopyWithPlaceholders,
            placeholdersInStringOrder: placeholdersInStringOrder
        )
    }
}

/// Unicode isolates help us avoid RTL/LTR formatting issues when substituting
/// strings into other strings.
///
/// See:
///     https://www.unicode.org/reports/tr9/#Explicit_Directional_Isolates
///     https://en.wikipedia.org/wiki/Bidirectional_text#Isolates
private extension Character {
    static let unicodeFirstStrongIsolate: Character = "\u{2068}"
    static let unicodePopDirectionalIsolate: Character = "\u{2069}"
}
