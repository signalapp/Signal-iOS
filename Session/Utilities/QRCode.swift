// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit

enum QRCode {
    /// Generates a QRCode for the give string
    ///
    /// **Note:** If the `hasBackground` value is true then the QRCode will be black and white and
    /// the `withRenderingMode(.alwaysTemplate)` won't work correctly on some iOS versions (eg. iOS 16)
    static func generate(for string: String, hasBackground: Bool) -> UIImage {
        let data = string.data(using: .utf8)
        var qrCodeAsCIImage: CIImage
        let filter1 = CIFilter(name: "CIQRCodeGenerator")!
        filter1.setValue(data, forKey: "inputMessage")
        qrCodeAsCIImage = filter1.outputImage!
        
        guard !hasBackground else {
            let filter2 = CIFilter(name: "CIFalseColor")!
            filter2.setValue(qrCodeAsCIImage, forKey: "inputImage")
            filter2.setValue(CIColor(color: .black), forKey: "inputColor0")
            filter2.setValue(CIColor(color: .white), forKey: "inputColor1")
            qrCodeAsCIImage = filter2.outputImage!
            
            let scaledQRCodeAsCIImage = qrCodeAsCIImage.transformed(by: CGAffineTransform(scaleX: 6.4, y: 6.4))
            return UIImage(ciImage: scaledQRCodeAsCIImage)
        }
        
        let filter2 = CIFilter(name: "CIColorInvert")!
        filter2.setValue(qrCodeAsCIImage, forKey: "inputImage")
        qrCodeAsCIImage = filter2.outputImage!
        let filter3 = CIFilter(name: "CIMaskToAlpha")!
        filter3.setValue(qrCodeAsCIImage, forKey: "inputImage")
        qrCodeAsCIImage = filter3.outputImage!
        
        let scaledQRCodeAsCIImage = qrCodeAsCIImage.transformed(by: CGAffineTransform(scaleX: 6.4, y: 6.4))
        
        // Note: It looks like some internal method was changed in iOS 16.0 where images
        // generated from a CIImage don't have the same color information as normal images
        // as a result tinting using the `alwaysTemplate` rendering mode won't work - to
        // work around this we convert the image to data and then back into an image
        let imageData: Data = UIImage(ciImage: scaledQRCodeAsCIImage).pngData()!
        return UIImage(data: imageData)!
    }
}
