//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// A generator producing QR codes for export from the app.
///
/// The QR codes are scaled up and have a black foreground over a white
/// background.
class ExportableQRCodeGenerator: QRCodeGenerator {
    func generateQRCode(data: Data) -> UIImage? {
        return generateQRCode(
            data: data,
            foregroundColor: .black,
            backgroundColor: .white,
            imageScale: 10
        )
    }
}
