// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import PromiseKit
import SessionUIKit

// The initial presentation is intended to be indistinguishable from the Launch Screen.
// After a delay we present some "loading" UI so the user doesn't think the app is frozen.
public class LoadingViewController: UIViewController {
    /// This value specifies the minimum expected duration which needs to be hit before the loading UI needs to be show
    private static let minExpectedDurationToShowLoading: TimeInterval = 5
    
    /// This value specifies the minimum expected duration which needs to be hit before the additional "might take a few minutes"
    /// label gets shown
    private static let minExpectedDurationAdditionalLabel: TimeInterval = 15
    
    private var isShowingProgress: Bool = false
    
    // MARK: - UI
    
    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    private var logoView: UIImageView = {
        let result: UIImageView = UIImageView(image: #imageLiteral(resourceName: "SessionGreen64"))
        result.contentMode = .scaleAspectFit
        result.themeShadowColorForced = .primary(.green)
        result.layer.shadowOffset = .zero
        result.layer.shadowRadius = 3
        result.layer.shadowOpacity = 0
        
        return result
    }()
    
    private var progressBar: UIProgressView = {
        let result: UIProgressView = UIProgressView(progressViewStyle: .bar)
        result.clipsToBounds = true
        result.progress = 0
        result.themeTintColorForced = .primary(.green)
        result.themeProgressTintColorForced = .theme(.classicDark, color: .textPrimary, alpha: 0.1)
        result.layer.cornerRadius = 6

        return result
    }()
    
    private var topLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = UIFont.systemFont(ofSize: Values.mediumFontSize)
        result.text = "DATABASE_VIEW_OVERLAY_TITLE".localized()
        result.themeTextColorForced = .theme(.classicDark, color: .textPrimary)
        result.textAlignment = .center
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping

        return result
    }()
    
    private var bottomLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = UIFont.systemFont(ofSize: Values.verySmallFontSize)
        result.text = "DATABASE_VIEW_OVERLAY_SUBTITLE".localized()
        result.themeTextColorForced = .theme(.classicDark, color: .textPrimary)
        result.textAlignment = .center
        result.numberOfLines = 0
        result.lineBreakMode = .byWordWrapping
        result.isHidden = true

        return result
    }()
    
    private lazy var labelStack: UIStackView = {
        let result: UIStackView = UIStackView()
        result.axis = .vertical
        result.alignment = .center
        result.spacing = 20
        result.alpha = 0
        
        return result
    }()
    
    // MARK: - Lifecycle

    override public func loadView() {
        self.view = UIView()
        
        self.view.themeBackgroundColorForced = .theme(.classicDark, color: .backgroundPrimary)

        self.view.addSubview(self.logoView)
        self.view.addSubview(self.labelStack)
        self.view.addSubview(self.bottomLabel)
        
        self.labelStack.addArrangedSubview(self.progressBar)
        self.labelStack.addArrangedSubview(self.topLabel)

        // Layout
        
        self.logoView.autoCenterInSuperview()
        self.logoView.autoSetDimension(.width, toSize: 64)
        self.logoView.autoSetDimension(.height, toSize: 64)
        
        self.progressBar.set(.height, to: (self.progressBar.layer.cornerRadius * 2))
        self.progressBar.set(.width, to: .width, of: self.view, multiplier: 0.5)
        
        self.labelStack.pin(.top, to: .bottom, of: self.logoView, withInset: 40)
        self.labelStack.pin(.left, to: .left, of: self.view)
        self.labelStack.pin(.right, to: .right, of: self.view)
        self.labelStack.setCompressionResistanceHigh()
        self.labelStack.setContentHuggingHigh()
        
        self.bottomLabel.pin(.top, to: .bottom, of: self.labelStack, withInset: 10)
        self.bottomLabel.pin(.left, to: .left, of: self.view)
        self.bottomLabel.pin(.right, to: .right, of: self.view)
        self.bottomLabel.setCompressionResistanceHigh()
        self.bottomLabel.setContentHuggingHigh()
    }
    
    // MARK: - Functions
    
    public func updateProgress(progress: CGFloat, minEstimatedTotalTime: TimeInterval) {
        guard minEstimatedTotalTime >= LoadingViewController.minExpectedDurationToShowLoading else { return }
        
        if !self.isShowingProgress {
            self.isShowingProgress = true
            self.bottomLabel.isHidden = (
                minEstimatedTotalTime < LoadingViewController.minExpectedDurationAdditionalLabel
            )
            
            UIView.animate(withDuration: 0.3) { [weak self] in
                self?.labelStack.alpha = 1
            }
            
            UIView.animate(
                withDuration: 1.95,
                delay: 0.05,
                options: [
                    .curveEaseInOut,
                    .autoreverse,
                    .repeat
                ],
                animations: { [weak self] in
                    self?.logoView.layer.shadowOpacity = 1
                },
                completion: nil
            )
        }
        
        self.progressBar.setProgress(Float(progress), animated: true)
    }
}
