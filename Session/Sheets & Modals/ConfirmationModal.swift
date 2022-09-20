// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import SessionUIKit

public class ConfirmationModal: Modal {
    public struct Info: Equatable, Hashable {
        enum State {
            case whenEnabled
            case whenDisabled
            case always
            
            func shouldShow(for value: Bool) -> Bool {
                switch self {
                    case .whenEnabled: return (value == true)
                    case .whenDisabled: return (value == false)
                    case .always: return true
                }
            }
        }
        
        let title: String
        let explanation: String?
        let attributedExplanation: NSAttributedString?
        let stateToShow: State
        let confirmTitle: String?
        let confirmStyle: ThemeValue
        let cancelTitle: String
        let cancelStyle: ThemeValue
        let dismissOnConfirm: Bool
        let onConfirm: ((UIViewController) -> ())?
        let afterClosed: (() -> ())?
        
        // MARK: - Initialization
        
        init(
            title: String,
            explanation: String? = nil,
            attributedExplanation: NSAttributedString? = nil,
            stateToShow: State = .always,
            confirmTitle: String? = nil,
            confirmStyle: ThemeValue = .alert_text,
            cancelTitle: String = "TXT_CANCEL_TITLE".localized(),
            cancelStyle: ThemeValue = .danger,
            dismissOnConfirm: Bool = true,
            onConfirm: ((UIViewController) -> ())? = nil,
            afterClosed: (() -> ())? = nil
        ) {
            self.title = title
            self.explanation = explanation
            self.attributedExplanation = attributedExplanation
            self.stateToShow = stateToShow
            self.confirmTitle = confirmTitle
            self.confirmStyle = confirmStyle
            self.cancelTitle = cancelTitle
            self.cancelStyle = cancelStyle
            self.dismissOnConfirm = dismissOnConfirm
            self.onConfirm = onConfirm
            self.afterClosed = afterClosed
        }
        
        // MARK: - Mutation
        
        public func with(
            onConfirm: ((UIViewController) -> ())? = nil,
            afterClosed: (() -> ())? = nil
        ) -> Info {
            return Info(
                title: self.title,
                explanation: self.explanation,
                stateToShow: self.stateToShow,
                confirmTitle: self.confirmTitle,
                confirmStyle: self.confirmStyle,
                cancelTitle: self.cancelTitle,
                cancelStyle: self.cancelStyle,
                dismissOnConfirm: self.dismissOnConfirm,
                onConfirm: (onConfirm ?? self.onConfirm),
                afterClosed: (afterClosed ?? self.afterClosed)
            )
        }
        
        // MARK: - Confirmance
        
        public static func == (lhs: ConfirmationModal.Info, rhs: ConfirmationModal.Info) -> Bool {
            return (
                lhs.title == rhs.title &&
                lhs.explanation == rhs.explanation &&
                lhs.attributedExplanation == rhs.attributedExplanation &&
                lhs.stateToShow == rhs.stateToShow &&
                lhs.confirmTitle == rhs.confirmTitle &&
                lhs.confirmStyle == rhs.confirmStyle &&
                lhs.cancelTitle == rhs.cancelTitle &&
                lhs.cancelStyle == rhs.cancelStyle &&
                lhs.dismissOnConfirm == rhs.dismissOnConfirm
            )
        }
        
        public func hash(into hasher: inout Hasher) {
            title.hash(into: &hasher)
            explanation.hash(into: &hasher)
            attributedExplanation.hash(into: &hasher)
            stateToShow.hash(into: &hasher)
            confirmTitle.hash(into: &hasher)
            confirmStyle.hash(into: &hasher)
            cancelTitle.hash(into: &hasher)
            cancelStyle.hash(into: &hasher)
            dismissOnConfirm.hash(into: &hasher)
        }
    }
    
    private let internalOnConfirm: (UIViewController) -> ()
    
    // MARK: - Components
    
    private lazy var titleLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .boldSystemFont(ofSize: Values.mediumFontSize)
        result.themeTextColor = .alert_text
        result.textAlignment = .center
        result.lineBreakMode = .byWordWrapping
        result.numberOfLines = 0
        
        return result
    }()
    
    private lazy var explanationLabel: UILabel = {
        let result: UILabel = UILabel()
        result.font = .systemFont(ofSize: Values.smallFontSize)
        result.themeTextColor = .alert_text
        result.textAlignment = .center
        result.lineBreakMode = .byWordWrapping
        result.numberOfLines = 0
        
        return result
    }()
    
    private lazy var confirmButton: UIButton = {
        let result: UIButton = Modal.createButton(
            title: "",
            titleColor: .danger
        )
        result.addTarget(self, action: #selector(confirmationPressed), for: .touchUpInside)
        
        return result
    }()
    
    private lazy var buttonStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ confirmButton, cancelButton ])
        result.axis = .horizontal
        result.distribution = .fillEqually
        
        return result
    }()
    
    private lazy var contentStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ titleLabel, explanationLabel ])
        result.axis = .vertical
        result.spacing = Values.smallSpacing
        result.isLayoutMarginsRelativeArrangement = true
        result.layoutMargins = UIEdgeInsets(
            top: Values.largeSpacing,
            leading: Values.largeSpacing,
            bottom: Values.verySmallSpacing,
            trailing: Values.largeSpacing
        )
        
        return result
    }()
    
    private lazy var mainStackView: UIStackView = {
        let result = UIStackView(arrangedSubviews: [ contentStackView, buttonStackView ])
        result.axis = .vertical
        result.spacing = Values.largeSpacing - Values.smallFontSize / 2
        
        return result
    }()
    
    // MARK: - Lifecycle
    
    init(info: Info) {
        self.internalOnConfirm = { viewController in
            if info.dismissOnConfirm {
                viewController.dismiss(animated: true)
            }
            
            info.onConfirm?(viewController)
        }
        
        super.init(afterClosed: info.afterClosed)
        
        self.modalPresentationStyle = .overFullScreen
        self.modalTransitionStyle = .crossDissolve
        
        // Set the content based on the provided info
        titleLabel.text = info.title
        
        // Note: We should only set the appropriate explanation/attributedExplanation value (as
        // setting both when one is null can result in the other being removed)
        if let explanation: String = info.explanation {
            explanationLabel.text = explanation
        }
        
        if let attributedExplanation: NSAttributedString = info.attributedExplanation {
            explanationLabel.attributedText = attributedExplanation
        }
    
        explanationLabel.isHidden = (
            info.explanation == nil &&
            info.attributedExplanation == nil
        )
        confirmButton.setTitle(info.confirmTitle, for: .normal)
        confirmButton.setThemeTitleColor(info.confirmStyle, for: .normal)
        confirmButton.isHidden = (info.confirmTitle == nil)
        cancelButton.setTitle(info.cancelTitle, for: .normal)
        cancelButton.setThemeTitleColor(info.cancelStyle, for: .normal)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func populateContentView() {
        contentView.addSubview(mainStackView)
        
        mainStackView.pin(to: contentView)
    }
    
    // MARK: - Interaction
    
    @objc private func confirmationPressed() {
        internalOnConfirm(self)
    }
}
