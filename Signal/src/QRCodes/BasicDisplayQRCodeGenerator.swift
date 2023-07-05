//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalUI

/// A generator that produces a "basic" QR code for display.
///
/// Specifically, the generated QR code has a dark foreground over a transparent
/// background.
class BasicDisplayQRCodeGenerator: QRCodeGenerator {
    func generateQRCode(data: Data) -> UIImage? {
        return generateQRCode(
            data: data,
            foregroundColor: Theme.lightThemePrimaryColor,
            backgroundColor: .clear,
            imageScale: nil
        )
    }
}
