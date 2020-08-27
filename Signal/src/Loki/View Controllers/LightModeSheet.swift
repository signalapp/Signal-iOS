
final class LightModeSheet : Sheet {

    override func populateContentView() {
        // Set up image view
        let imageView = UIImageView(image: #imageLiteral(resourceName: "Sun"))
        // Set up title label
        let titleLabel = UILabel()
        titleLabel.textColor = Colors.text
        titleLabel.font = .boldSystemFont(ofSize: isIPhone5OrSmaller ? Values.largeFontSize : Values.veryLargeFontSize)
        titleLabel.text = "Light Mode"
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        // Set up top stack view
        let topStackView = UIStackView(arrangedSubviews: [ imageView, titleLabel ])
        topStackView.axis = .vertical
        topStackView.spacing = Values.largeSpacing
        topStackView.alignment = .center
        // Set up explanation label
        let explanationLabel = UILabel()
        explanationLabel.textColor = Colors.text
        explanationLabel.font = .systemFont(ofSize: Values.smallFontSize)
        explanationLabel.text = """
        Who left the lights on? bla bla bla

        Feeling the dark side more? Just pop into the in-app settings and tap the app mode button in the top-right to toggle dark mode again.
        """
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping
        // Set up OK button
        let okButton = Button(style: .prominentOutline, size: .large)
        okButton.set(.width, to: 240)
        okButton.setTitle(NSLocalizedString("OK", comment: ""), for: UIControl.State.normal)
        okButton.addTarget(self, action: #selector(close), for: UIControl.Event.touchUpInside)
        // Set up main stack view
        let stackView = UIStackView(arrangedSubviews: [ topStackView, explanationLabel, okButton ])
        stackView.axis = .vertical
        stackView.spacing = Values.veryLargeSpacing
        stackView.alignment = .center
        // Set up constraints
        contentView.addSubview(stackView)
        stackView.pin(.leading, to: .leading, of: contentView, withInset: Values.veryLargeSpacing)
        stackView.pin(.top, to: .top, of: contentView, withInset: Values.largeSpacing)
        contentView.pin(.trailing, to: .trailing, of: stackView, withInset: Values.veryLargeSpacing)
        contentView.pin(.bottom, to: .bottom, of: stackView, withInset: Values.veryLargeSpacing + overshoot)
    }
}
