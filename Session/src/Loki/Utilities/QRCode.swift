
enum QRCode {
    
    static func generate(for string: String, isInverted: Bool = false, hasBackground: Bool = false) -> UIImage {
        let data = string.data(using: .utf8)
        var qrCodeAsCIImage: CIImage
        let filter1 = CIFilter(name: "CIQRCodeGenerator")!
        filter1.setValue(data, forKey: "inputMessage")
        qrCodeAsCIImage = filter1.outputImage!
        if hasBackground {
            let filter2 = CIFilter(name: "CIFalseColor")!
            filter2.setValue(qrCodeAsCIImage, forKey: "inputImage")
            filter2.setValue(CIColor(color: UIColor(hex: isInverted ? 0xFFFFFF : 0x000000)), forKey: "inputColor0")
            filter2.setValue(CIColor(color: UIColor(hex: isInverted ? 0x1B1B1B : 0xFFFFFF)), forKey: "inputColor1")
            qrCodeAsCIImage = filter2.outputImage!
        } else {
            let filter2 = CIFilter(name: "CIColorInvert")!
            filter2.setValue(qrCodeAsCIImage, forKey: "inputImage")
            qrCodeAsCIImage = filter2.outputImage!
            let filter3 = CIFilter(name: "CIMaskToAlpha")!
            filter3.setValue(qrCodeAsCIImage, forKey: "inputImage")
            qrCodeAsCIImage = filter3.outputImage!
        }
        let scaledQRCodeAsCIImage = qrCodeAsCIImage.transformed(by: CGAffineTransform(scaleX: 6.4, y: 6.4))
        return UIImage(ciImage: scaledQRCodeAsCIImage)
    }
}
