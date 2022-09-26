// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import PureLayout
import SessionUIKit
import SessionUtilitiesKit
import NVActivityIndicatorView

class EmptySearchResultCell: UITableViewCell {
    private lazy var messageLabel: UILabel = {
        let result = UILabel()
        result.text = "CONVERSATION_SEARCH_NO_RESULTS".localized()
        result.themeTextColor = .textPrimary
        result.textAlignment = .center
        result.numberOfLines = 3
        
        return result
    }()
    
    private let spinner: NVActivityIndicatorView = {
        let result: NVActivityIndicatorView = NVActivityIndicatorView(
            frame: CGRect.zero,
            type: .circleStrokeSpin,
            color: .black,
            padding: nil
        )
        result.set(.width, to: 40)
        result.set(.height, to: 40)
        
        ThemeManager.onThemeChange(observer: result) { [weak result] theme, _ in
            guard let textPrimary: UIColor = theme.color(for: .textPrimary) else { return }
            
            result?.color = textPrimary
        }
        
        return result
    }()
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        themeBackgroundColor = .clear
        selectionStyle = .none
        
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
        }
        else {
            spinner.stopAnimating()
            messageLabel.isHidden = false
        }
    }
}
