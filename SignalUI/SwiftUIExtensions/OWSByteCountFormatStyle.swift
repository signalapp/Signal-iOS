//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct OWSByteCountFormatStyle: FormatStyle {
    private let fudgeBase2ToBase10: Bool
    private let zeroPadFractionDigits: Bool

    /// - Parameter fudgeBase2ToBase10
    /// Whether the given byte count should be "fudged" from a base2 to base10
    /// value. See `OWSBase2ByteCountFudger` for more.
    /// - Parameter zeroPadFractionDigits
    /// Whether the formatted string should zero-pad fraction digits to maintain
    /// a consistent string length across multiple formatting instances. Callers
    /// formatting a single fixed value, rather than a value that may change
    /// in-place, may prefer to pass `false` to avoid unnecessary zero-padding.
    public init(
        fudgeBase2ToBase10: Bool = false,
        zeroPadFractionDigits: Bool = true,
    ) {
        self.fudgeBase2ToBase10 = fudgeBase2ToBase10
        self.zeroPadFractionDigits = zeroPadFractionDigits
    }

    public func format(_ byteCountParam: UInt64) -> String {
        let byteCount: UInt64
        if
            fudgeBase2ToBase10,
            let fudged = OWSBase2ByteCountFudger.fudgeBase2ToBase10(byteCountParam)
        {
            byteCount = fudged
        } else {
            byteCount = byteCountParam
        }

        let byteFormatter = ByteCountFormatter()
        // Use KB, MB, GB, etc as appropriate.
        byteFormatter.allowedUnits = .useAll
        // Assume the byte count is base-10, i.e. "1000 bytes / 1 KB". See
        // OWSBase2ByteCountFudger for more.
        byteFormatter.countStyle = .decimal
        // Don't use, for example, the word "zero" instead of the numeral "0".
        byteFormatter.allowsNonnumericFormatting = false
        // Zero-pad fractions to keep a fixed number of digits in the string, if
        // we format multiple different values that might otherwise produce
        // different fractional lengths. Otherwise, it can look "jumpy"; e.g.,
        // going from 400 MB to 400.1 MB.
        //
        // The number of digits is managed by the formatter: see `isAdaptive`,
        // which defaults to true.
        byteFormatter.zeroPadsFractionDigits = zeroPadFractionDigits

        return byteFormatter.string(fromByteCount: Int64(clamping: byteCount))
    }
}

extension FormatStyle where Self == OWSByteCountFormatStyle {
    public static func owsByteCount(
        fudgeBase2ToBase10: Bool = false,
        zeroPadFractionDigits: Bool = true,
    ) -> OWSByteCountFormatStyle {
        return OWSByteCountFormatStyle(
            fudgeBase2ToBase10: fudgeBase2ToBase10,
            zeroPadFractionDigits: zeroPadFractionDigits,
        )
    }
}

// MARK: -

enum OWSBase2ByteCountFudger {
    /// If the given byte count is a multiple of an exponentiation of 1024,
    /// returns the byte count as a multiple of the corresponding exponentiation
    /// of 1000 instead. In other words, fudges base-2 byte counts to their
    /// roughly-approximate base-10 byte count instead.
    ///
    /// For example, given the value `107_374_182_400` (or `100 * 1024^3`, aka
    /// "100 gibibytes/GiB"), returns `100_000_000_000` (or `100 * 1000^3`, aka
    /// "100 gigabytes/GB").
    ///
    /// See https://simple.wikipedia.org/wiki/Gibibyte if you, like me, were
    /// surprised to learn about base-2 byte values.
    ///
    /// - Note
    /// At the time of writing, the use case for this is the Backups
    /// `storageAllowanceBytes` value, which is configured on the server to be a
    /// GiB value rather than GB.
    static func fudgeBase2ToBase10(_ byteCount: UInt64) -> UInt64? {
        if byteCount == 0 { return 0 }

        // Cut byteCount down by 1024s until it can't be cut anymore. At that
        // point it'll represent the "multiple"; e.g., we were given 37 MiB and
        // are left with 37.
        var byteCount = byteCount
        var exponentiation = 0
        while byteCount >= 1024 {
            if byteCount % 1024 != 0 {
                // In the end, not roundly divisible by an exponentiation of
                // 1024. Bail.
                return nil
            }

            byteCount /= 1024
            exponentiation += 1
        }

        // Then, build it back up using 1000s.
        //
        // This can't overflow since 1000 < 1024, so the resulting value will
        // always be smaller than the passed-in value.
        for _ in 0..<exponentiation {
            byteCount *= 1000
        }
        return byteCount
    }
}
