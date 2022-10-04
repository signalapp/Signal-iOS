// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import NVActivityIndicatorView
import SessionUIKit
import SessionMessagingKit
import SessionUtilitiesKit

public final class VoiceMessageView: UIView {
    private static let width: CGFloat = 160
    private static let toggleContainerSize: CGFloat = 20
    private static let inset = Values.smallSpacing
    
    // MARK: - UI
    
    private lazy var progressViewRightConstraint = progressView.pin(.right, to: .right, of: self, withInset: -VoiceMessageView.width)
    
    private lazy var progressView: UIView = {
        let result: UIView = UIView()
        result.themeBackgroundColor = .messageBubble_overlay
        
        return result
    }()
    
    private lazy var toggleContainer: UIView = {
        let result: UIView = UIView()
        result.themeBackgroundColor = .backgroundSecondary
        result.set(.width, to: VoiceMessageView.toggleContainerSize)
        result.set(.height, to: VoiceMessageView.toggleContainerSize)
        result.layer.masksToBounds = true
        result.layer.cornerRadius = (VoiceMessageView.toggleContainerSize / 2)
        
        return result
    }()

    private lazy var toggleImageView: UIImageView = {
        let result: UIImageView = UIImageView(
            image: UIImage(named: "Play")?.withRenderingMode(.alwaysTemplate)
        )
        result.contentMode = .scaleAspectFit
        result.themeTintColor = .textPrimary
        result.set(.width, to: 8)
        result.set(.height, to: 8)
        
        return result
    }()

    private let loader: NVActivityIndicatorView = {
        let result: NVActivityIndicatorView = NVActivityIndicatorView(
            frame: .zero,
            type: .circleStrokeSpin,
            color: .black,
            padding: nil
        )
        result.set(.width, to: VoiceMessageView.toggleContainerSize + 2)
        result.set(.height, to: VoiceMessageView.toggleContainerSize + 2)
        
        ThemeManager.onThemeChange(observer: result) { [weak result] theme, _ in
            guard let textPrimary: UIColor = theme.color(for: .textPrimary) else { return }
            
            result?.color = textPrimary
        }
        
        return result
    }()

    private lazy var countdownLabelContainer: UIView = {
        let result: UIView = UIView()
        result.clipsToBounds = true
        result.themeBackgroundColor = .backgroundSecondary
        result.set(.height, to: VoiceMessageView.toggleContainerSize)
        result.set(.width, to: 44)
        
        return result
    }()

    private lazy var countdownLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.text = "0:00"
        result.themeTextColor = .textPrimary
        
        return result
    }()

    private lazy var speedUpLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.text = "1.5x"
        result.themeTextColor = .textPrimary
        result.textAlignment = .center
        result.alpha = 0
        
        return result
    }()

    // MARK: - Lifecycle
    
    init() {
        super.init(frame: CGRect.zero)
        
        setUpViewHierarchy()
    }

    override init(frame: CGRect) {
        preconditionFailure("Use init(viewItem:) instead.")
    }

    required init?(coder: NSCoder) {
        preconditionFailure("Use init(viewItem:) instead.")
    }

    private func setUpViewHierarchy() {
        let toggleContainerSize = VoiceMessageView.toggleContainerSize
        let inset = VoiceMessageView.inset
        
        // Width & height
        set(.width, to: VoiceMessageView.width)
        
        // Toggle
        toggleContainer.addSubview(toggleImageView)
        toggleImageView.center(in: toggleContainer)
        
        // Line
        let lineView = UIView()
        lineView.themeBackgroundColor = .backgroundSecondary
        lineView.set(.height, to: 1)
        
        // Countdown label
        countdownLabelContainer.addSubview(countdownLabel)
        countdownLabel.center(in: countdownLabelContainer)
        
        // Speed up label
        countdownLabelContainer.addSubview(speedUpLabel)
        speedUpLabel.center(in: countdownLabelContainer)
        
        // Constraints
        addSubview(progressView)
        progressView.pin(.left, to: .left, of: self)
        progressView.pin(.top, to: .top, of: self)
        progressViewRightConstraint.isActive = true
        progressView.pin(.bottom, to: .bottom, of: self)
        addSubview(toggleContainer)
        
        toggleContainer.pin(.left, to: .left, of: self, withInset: inset)
        toggleContainer.pin(.top, to: .top, of: self, withInset: inset)
        toggleContainer.pin(.bottom, to: .bottom, of: self, withInset: -inset)
        addSubview(lineView)
        
        lineView.pin(.left, to: .right, of: toggleContainer)
        lineView.center(.vertical, in: self)
        addSubview(countdownLabelContainer)
        
        countdownLabelContainer.pin(.left, to: .right, of: lineView)
        countdownLabelContainer.pin(.right, to: .right, of: self, withInset: -inset)
        countdownLabelContainer.center(.vertical, in: self)
        
        addSubview(loader)
        loader.center(in: toggleContainer)
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        
        countdownLabelContainer.layer.cornerRadius = (countdownLabelContainer.bounds.height / 2)
    }

    // MARK: - Updating
    
    public func update(
        with attachment: Attachment,
        isPlaying: Bool,
        progress: TimeInterval,
        playbackRate: Double,
        oldPlaybackRate: Double
    ) {
        switch attachment.state {
            case .downloaded, .uploaded:
                loader.isHidden = true
                loader.stopAnimating()
                
                toggleImageView.image = (isPlaying ? UIImage(named: "Pause") : UIImage(named: "Play"))?
                    .withRenderingMode(.alwaysTemplate)
                countdownLabel.text = max(0, (floor(attachment.duration.defaulting(to: 0) - progress)))
                    .formatted(format: .hoursMinutesSeconds)
                
                guard let duration: TimeInterval = attachment.duration, duration > 0, progress > 0 else {
                    return progressViewRightConstraint.constant = -VoiceMessageView.width
                }
                
                let fraction: Double = (progress / duration)
                progressViewRightConstraint.constant = -(VoiceMessageView.width * (1 - fraction))
                
                // If the playback rate changed then show the 'speedUpLabel' briefly
                guard playbackRate > oldPlaybackRate else { return }
                
                UIView.animate(withDuration: 0.25) { [weak self] in
                    self?.countdownLabel.alpha = 0
                    self?.speedUpLabel.alpha = 1
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1250)) {
                    UIView.animate(withDuration: 0.25) { [weak self] in
                        self?.countdownLabel.alpha = 1
                        self?.speedUpLabel.alpha = 0
                    }
                }
                
            default:
                if !loader.isAnimating {
                    loader.startAnimating()
                }
        }
    }
}
