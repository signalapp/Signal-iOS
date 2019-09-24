
@objc(LKQRCodeModal)
final class QRCodeModal : Modal {
    
    override func populateContentView() {
        // Label
        let label = UILabel()
        label.font = UIFont.ows_dynamicTypeSubheadlineClamped
        label.text = NSLocalizedString("This is your personal QR code. Other people can scan it to start a secure conversation with you.", comment: "")
        label.numberOfLines = 0
        label.textAlignment = .center
        label.lineBreakMode = .byWordWrapping
        label.textColor = UIColor.ows_white
        // Image view
        let imageView = UIImageView()
        let hexEncodedPublicKey = OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
        let data = hexEncodedPublicKey.data(using: .utf8)
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(data, forKey: "inputMessage")
        let qrCodeAsCIImage = filter.outputImage!
        let scaledQRCodeAsCIImage = qrCodeAsCIImage.transformed(by: CGAffineTransform(scaleX: 4.8, y: 4.8))
        let qrCode = UIImage(ciImage: scaledQRCodeAsCIImage)
        imageView.image = qrCode
        // Cancel button
        let buttonHeight = cancelButton.button.titleLabel!.font.pointSize * 48 / 17
        cancelButton.set(.height, to: buttonHeight)
        // Stack view
        let stackView = UIStackView(arrangedSubviews: [ UIView.spacer(withHeight: 2), label, UIView.spacer(withHeight: 2), imageView, cancelButton ])
        stackView.axis = .vertical
        stackView.spacing = 16
        stackView.alignment = .center
        contentView.addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: contentView, withInset: 16)
        stackView.pin(.top, to: .top, of: contentView, withInset: 16)
        contentView.pin(.trailing, to: .trailing, of: stackView, withInset: 16)
        contentView.pin(.bottom, to: .bottom, of: stackView, withInset: 16)
    }
}
