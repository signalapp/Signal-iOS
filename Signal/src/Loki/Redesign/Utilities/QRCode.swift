
enum QRCode {
    
    static func generate(for string: String, isInverted: Bool = true) -> UIImage {
        let data = string.data(using: .utf8)
        var qrCodeAsCIImage: CIImage
        let filter1 = CIFilter(name: "CIQRCodeGenerator")!
        filter1.setValue(data, forKey: "inputMessage")
        qrCodeAsCIImage = filter1.outputImage!
        if isInverted {
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
