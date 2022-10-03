// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import PromiseKit
import SessionUIKit
import SessionMessagingKit
import SessionSnodeKit
import SignalUtilitiesKit

final class PNModeVC: BaseVC, OptionViewDelegate {

    private var optionViews: [OptionView] {
        [ apnsOptionView, backgroundPollingOptionView ]
    }

    private var selectedOptionView: OptionView? {
        return optionViews.first { $0.isSelected }
    }

    // MARK: - Components
    
    private lazy var apnsOptionView: OptionView = {
        let result: OptionView = OptionView(
            title: "fast_mode".localized(),
            explanation: "fast_mode_explanation".localized(),
            delegate: self,
            isRecommended: true
        )
        result.accessibilityLabel = "Fast mode option"
        
        return result
    }()
    
    private lazy var backgroundPollingOptionView: OptionView = {
        let result: OptionView = OptionView(
            title: "slow_mode".localized(),
            explanation: "slow_mode_explanation".localized(),
            delegate: self
        )
        result.accessibilityLabel = "Slow mode option"
        
        return result
    }()

    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setUpNavBarSessionIcon()
        
        let learnMoreButton = UIBarButtonItem(image: #imageLiteral(resourceName: "ic_info"), style: .plain, target: self, action: #selector(learnMore))
        learnMoreButton.themeTintColor = .textPrimary
        navigationItem.rightBarButtonItem = learnMoreButton
        
        // Set up title label
        let titleLabel = UILabel()
        titleLabel.font = .boldSystemFont(ofSize: isIPhone5OrSmaller ? Values.largeFontSize : Values.veryLargeFontSize)
        titleLabel.text = "vc_pn_mode_title".localized()
        titleLabel.themeTextColor = .textPrimary
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.numberOfLines = 0
        
        // Set up spacers
        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()
        let registerButtonBottomOffsetSpacer = UIView()
        registerButtonBottomOffsetSpacer.set(.height, to: Values.onboardingButtonBottomOffset)
        
        // Set up register button
        let registerButton = SessionButton(style: .filled, size: .large)
        registerButton.setTitle("continue_2".localized(), for: .normal)
        registerButton.addTarget(self, action: #selector(register), for: UIControl.Event.touchUpInside)
        
        // Set up register button container
        let registerButtonContainer = UIView(wrapping: registerButton, withInsets: UIEdgeInsets(top: 0, leading: Values.massiveSpacing, bottom: 0, trailing: Values.massiveSpacing), shouldAdaptForIPadWithWidth: Values.iPadButtonWidth)
        
        // Set up options stack view
        let optionsStackView = UIStackView(arrangedSubviews: optionViews)
        optionsStackView.axis = .vertical
        optionsStackView.spacing = Values.smallSpacing
        optionsStackView.alignment = .fill
        
        // Set up top stack view
        let topStackView = UIStackView(arrangedSubviews: [ titleLabel, UIView.spacer(withHeight: isIPhone6OrSmaller ? Values.mediumSpacing : Values.veryLargeSpacing), optionsStackView ])
        topStackView.axis = .vertical
        topStackView.alignment = .fill
        
        // Set up top stack view container
        let topStackViewContainer = UIView(wrapping: topStackView, withInsets: UIEdgeInsets(top: 0, leading: Values.veryLargeSpacing, bottom: 0, trailing: Values.veryLargeSpacing))
        
        // Set up main stack view
        let mainStackView = UIStackView(arrangedSubviews: [ topSpacer, topStackViewContainer, bottomSpacer, registerButtonContainer, registerButtonBottomOffsetSpacer ])
        mainStackView.axis = .vertical
        mainStackView.alignment = .fill
        view.addSubview(mainStackView)
        mainStackView.pin(to: view)
        topSpacer.heightAnchor.constraint(equalTo: bottomSpacer.heightAnchor, multiplier: 1).isActive = true
        
        // Preselect APNs mode
        optionViews[0].isSelected = true
    }

    // MARK: - Interaction
    
    @objc private func learnMore() {
        guard let url: URL = URL(string: "https://getsession.org/faq/#privacy") else { return }
        
        UIApplication.shared.open(url)
    }

    func optionViewDidActivate(_ optionView: OptionView) {
        optionViews.filter { $0 != optionView }.forEach { $0.isSelected = false }
    }

    @objc private func register() {
        guard selectedOptionView != nil else {
            let modal: ConfirmationModal = ConfirmationModal(
                targetView: self.view,
                info: ConfirmationModal.Info(
                    title: "vc_pn_mode_no_option_picked_modal_title".localized(),
                    cancelTitle: "BUTTON_OK".localized(),
                    cancelStyle: .alert_text
                )
            )
            self.present(modal, animated: true)
            return
        }
        UserDefaults.standard[.isUsingFullAPNs] = (selectedOptionView == apnsOptionView)
        
        Identity.didRegister()
        
        // Go to the home screen
        let homeVC: HomeVC = HomeVC()
        self.navigationController?.setViewControllers([ homeVC ], animated: true)
        
        // Now that we have registered get the Snode pool and sync push tokens
        GetSnodePoolJob.run()
        SyncPushTokensJob.run(uploadOnlyIfStale: false)
    }
}
