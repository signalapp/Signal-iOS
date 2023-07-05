//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// A generator that produces QR codes suitable for export from the app.
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
