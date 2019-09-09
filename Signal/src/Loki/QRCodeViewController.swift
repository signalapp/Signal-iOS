
final class QRCodeViewController : OWSViewController {
    
    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask { return .portrait}
    public override var preferredStatusBarStyle: UIStatusBarStyle { return .lightContent}
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.lokiDarkestGray()
        let stackView = UIStackView(arrangedSubviews: [])
        stackView.axis = .vertical
        stackView.spacing = 32
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            view.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: 32)
        ])
        let label = UILabel()
        label.font = UIFont.ows_dynamicTypeSubheadlineClamped
        label.text = NSLocalizedString("This is your personal QR code. Other people can scan it to start a secure conversation with you.", comment: "")
        label.numberOfLines = 0
        label.textAlignment = .center
        label.lineBreakMode = .byWordWrapping
        label.textColor = UIColor.ows_white
        stackView.addArrangedSubview(label)
        let imageView = UIImageView()
        let hexEncodedPublicKey = OWSIdentityManager.shared().identityKeyPair()!.hexEncodedPublicKey
        let data = hexEncodedPublicKey.data(using: .utf8)
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(data, forKey: "inputMessage")
        let qrCodeAsCIImage = filter.outputImage!
        let scaledQRCodeAsCIImage = qrCodeAsCIImage.transformed(by: CGAffineTransform(scaleX: 6.4, y: 6.4))
        let qrCode = UIImage(ciImage: scaledQRCodeAsCIImage)
        imageView.image = qrCode
        stackView.addArrangedSubview(imageView)
    }
}
