//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct OWSByteCountFormatStyle: FormatStyle {
    private let style: ByteCountFormatStyle.Style

    public init() {
        self.style = .decimal
    }

    public func format(_ byteCount: Int64) -> String {
        let byteFormatter = ByteCountFormatter()
        // Use KB, MB, GB, etc as appropriate.
        byteFormatter.allowedUnits = .useAll
        byteFormatter.countStyle = .decimal
        // Don't use, for example, the word "zero" instead of the numeral "0".
        byteFormatter.allowsNonnumericFormatting = false
        // Zero-pad fractions (the number of digits is controlled by the
        // formatter: see `isAdaptive`, which defaults to true) to keep a fixed
        // number of digits. Otherwise, it can look "jumpy" (e.g., going from
        // 400 MB to 400.1 MB).
        byteFormatter.zeroPadsFractionDigits = true

        return byteFormatter.string(fromByteCount: byteCount)
    }
}

extension FormatStyle where Self == OWSByteCountFormatStyle {
    public static var owsByteCount: OWSByteCountFormatStyle {
        return OWSByteCountFormatStyle()
    }
}
