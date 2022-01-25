// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import NVActivityIndicatorView

class EmptySearchResultCell: UITableViewCell {
    static let reuseIdentifier = "EmptySearchResultCell"

    private lazy var messageLabel: UILabel = {
        let result = UILabel()
        result.textAlignment = .center
        result.numberOfLines = 3
        result.textColor = Colors.text
        result.text = NSLocalizedString("CONVERSATION_SEARCH_NO_RESULTS", comment: "")
        return result
    }()
    
    private lazy var spinner: NVActivityIndicatorView = {
        let result = NVActivityIndicatorView(frame: CGRect.zero, type: .circleStrokeSpin, color: Colors.text, padding: nil)
        result.set(.width, to: 40)
        result.set(.height, to: 40)
        return result
    }()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = .clear
        
        contentView.addSubview(messageLabel)
        messageLabel.autoSetDimension(.height, toSize: 150)
        messageLabel.autoPinEdge(toSuperviewMargin: .top, relation: .greaterThanOrEqual)
        messageLabel.autoPinEdge(toSuperviewMargin: .leading, relation: .greaterThanOrEqual)
        messageLabel.autoPinEdge(toSuperviewMargin: .bottom, relation: .greaterThanOrEqual)
        messageLabel.autoPinEdge(toSuperviewMargin: .trailing, relation: .greaterThanOrEqual)
        messageLabel.autoVCenterInSuperview()
        messageLabel.autoHCenterInSuperview()
        messageLabel.setContentHuggingHigh()
        messageLabel.setCompressionResistanceHigh()

        contentView.addSubview(spinner)
        spinner.autoCenterInSuperview()
    }

    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    public func configure(isLoading: Bool) {
        if isLoading {
            // Calling stopAnimating() here is a workaround for
            // the spinner won't change its colour as the theme changed.
            spinner.stopAnimating()
            spinner.startAnimating()
            messageLabel.isHidden = true
        } else {
            spinner.stopAnimating()
            messageLabel.isHidden = false
        }
    }
}
