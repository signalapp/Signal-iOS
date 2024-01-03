//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging

class CallControlsConfirmationToastView: UIView {
    enum ControlType {
        case mute(isOn: Bool)
        case speakerphone(isOn: Bool)
        case ring(isOn: Bool)

        var imageName: String {
            switch self {
            case .mute(let isOn):
                if isOn {
                    return "mic-slash"
                } else {
                    return "mic"
                }
            case .speakerphone(let isOn):
                if isOn {
                    return "speaker"
                } else {
                    return "speaker-slash"
                }
            case .ring(let isOn):
                if isOn {
                    return "bell"
                } else {
                    return "bell-slash"
                }
            }
        }

        var text: String {
            switch self {
            case .mute(let isOn):
                if isOn {
                    return OWSLocalizedString(
                        "MUTE_CONFIRMATION_TOAST_LABEL",
                        comment: "Text for a toast confirming that the mic has been muted for a call."
                    )
                } else {
                    return OWSLocalizedString(
                        "UNMUTE_CONFIRMATION_TOAST_LABEL",
                        comment: "Text for a toast confirming that the mic has been unmuted for a call."
                    )
                }
            case .speakerphone(let isOn):
                if isOn {
                    return OWSLocalizedString(
                        "SPEAKERPHONE_ON_CONFIRMATION_TOAST_LABEL",
                        comment: "Text for a toast confirming that the speakerphone has been turned on for a call."
                    )
                } else {
                    return OWSLocalizedString(
                        "SPEAKERPHONE_OFF_CONFIRMATION_TOAST_LABEL",
                        comment: "Text for a toast confirming that the speakerphone has been turned off for a call."
                    )
                }
            case .ring(let isOn):
                if isOn {
                    return OWSLocalizedString(
                        "RING_ON_CONFIRMATION_TOAST_LABEL",
                        comment: "Text for a toast confirming that ringing has been turned on for a call."
                    )
                } else {
                    return OWSLocalizedString(
                        "RING_OFF_CONFIRMATION_TOAST_LABEL",
                        comment: "Text for a toast confirming that ringing has been turned off for a call."
                    )
                }
            }
        }
    }

    private enum Style {
        private static let opacity = UIAccessibility.isReduceTransparencyEnabled ? 0.8 : 0.6
        static let toastBackgroundColor = UIColor(red: 0.29, green: 0.29, blue: 0.29, alpha: opacity)
        static let textAndImageColor = UIColor(red: 0.91, green: 0.91, blue: 0.91, alpha: 1)
        static let cornerRadius: CGFloat = 20
        static let spacing: CGFloat = 8
        static let horizontalMargin: CGFloat = 12
        static let verticalMargin: CGFloat = 10
        static let font: UIFont = .dynamicTypeBody2
        static let imageDimension: CGFloat = 16
    }

    init(state: ControlType) {
        super.init(frame: .zero)

        // Image view
        let imageView = UIImageView(image: UIImage(named: state.imageName))
        imageView.tintColor = Style.textAndImageColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: Style.imageDimension),
            imageView.heightAnchor.constraint(equalToConstant: Style.imageDimension)
        ])
        // Label
        let label = UILabel()
        label.textColor = Style.textAndImageColor
        label.text = state.text
        label.font = Style.font
        // Stack
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = Style.spacing
        stackView.alignment = .center
        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(label)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        // Blur view
        let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
        blurView.translatesAutoresizingMaskIntoConstraints = false
        // Container view
        let containerView = UIView()
        containerView.backgroundColor = Style.toastBackgroundColor
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(stackView)
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: stackView.leadingAnchor, constant: -Style.horizontalMargin),
            containerView.trailingAnchor.constraint(equalTo: stackView.trailingAnchor, constant: Style.horizontalMargin),
            containerView.bottomAnchor.constraint(equalTo: stackView.bottomAnchor, constant: Style.verticalMargin),
            containerView.topAnchor.constraint(equalTo: stackView.topAnchor, constant: -Style.verticalMargin),
        ])
        // Self
        self.addSubview(blurView)
        self.addSubview(containerView)
        self.layer.cornerRadius = Style.cornerRadius
        self.clipsToBounds = true
        blurView.autoPinEdgesToSuperviewEdges()
        containerView.autoPinEdgesToSuperviewEdges()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class CallControlsConfirmationToastManager {
    typealias ControlType = CallControlsConfirmationToastView.ControlType

    private let presentingContainerView: UIView

    init(presentingContainerView: UIView) {
        self.presentingContainerView = presentingContainerView
    }

    func toastInducingCallControlChangeDidOccur(state: ControlType) {
        self.presentToast(from: self.presentingContainerView, state: state)
    }

    private var toast: UIView?

    private func presentToast(from view: UIView, state: ControlType) {
        if let oldToast = self.toast {
            // Handle case where new toast is triggered before old
            // toast's disappearance animation completes.
            oldToast.layer.removeAllAnimations()
            oldToast.removeFromSuperview()
        }

        let toast = CallControlsConfirmationToastView(state: state)
        self.toast = toast
        toast.alpha = 0
        view.addSubview(toast)
        toast.transform = .scale(0.8)
        toast.autoPinEdgesToSuperviewEdges()

        let appearAnimator = UIViewPropertyAnimator(
            duration: 0.2,
            springDamping: 0.8,
            springResponse: 0.2
        )
        appearAnimator.addAnimations {
            toast.alpha = 1
            toast.transform = .identity
        }
        appearAnimator.addCompletion { _ in
            let disappearAnimator = UIViewPropertyAnimator(
                duration: 0.2,
                springDamping: 0.8,
                springResponse: 0.2
            )
            disappearAnimator.addAnimations {
                toast.alpha = 0
            }
            disappearAnimator.addCompletion { _ in
                toast.removeFromSuperview()
            }
            disappearAnimator.startAnimation(afterDelay: 2)
        }
        appearAnimator.startAnimation()
    }
}
