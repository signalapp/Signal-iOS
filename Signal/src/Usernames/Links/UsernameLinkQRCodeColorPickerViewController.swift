//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
import SignalServiceKit
import SignalUI

protocol UsernameLinkQRCodeColorPickerDelegate: SheetDismissalDelegate {
    func didFinalizeSelectedColor(color: Usernames.QRCodeColor)
}

class UsernameLinkQRCodeColorPickerViewController: OWSTableViewController2 {
    private let startingColor: Usernames.QRCodeColor
    private var currentColor: Usernames.QRCodeColor

    private let username: String
    private let qrCodeTemplateImage: UIImage

    private weak var colorPickerDelegate: UsernameLinkQRCodeColorPickerDelegate?

    init(
        currentColor: Usernames.QRCodeColor,
        username: String,
        qrCodeTemplateImage: UIImage,
        delegate: UsernameLinkQRCodeColorPickerDelegate
    ) {
        owsAssert(qrCodeTemplateImage.renderingMode == .alwaysTemplate)

        self.startingColor = currentColor
        self.currentColor = currentColor

        self.username = username
        self.qrCodeTemplateImage = qrCodeTemplateImage

        self.colorPickerDelegate = delegate

        super.init()
    }

    // MARK: - Table contents

    /// Build a view containing the QR code, username, and colored background.
    ///
    /// This view has a fixed width, built around the fixed-width QR code.
    private func buildQRCodeView() -> UIView {
        let qrCodeImageView: UIImageView = {
            let imageView = UIImageView(image: qrCodeTemplateImage)

            imageView.tintColor = currentColor.foreground
            imageView.autoSetDimensions(to: .square(184))

            return imageView
        }()

        let qrCodePaddingView: UIView = {
            let view = UIView()

            view.backgroundColor = .ows_white
            view.layer.borderColor = currentColor.paddingBorder.cgColor
            view.layer.borderWidth = 2
            view.layer.cornerRadius = 12
            view.layoutMargins = UIEdgeInsets(margin: 16)

            view.addSubview(qrCodeImageView)
            qrCodeImageView.autoPinEdgesToSuperviewMargins()

            return view
        }()

        let usernameLabel: UILabel = {
            let label = UILabel()

            label.textColor = currentColor.username
            label.numberOfLines = 0
            label.lineBreakMode = .byCharWrapping
            label.textAlignment = .center
            label.font = .dynamicTypeHeadline.semibold()
            label.text = username

            return label
        }()

        let backgroundView = UIView()
        backgroundView.backgroundColor = currentColor.background
        backgroundView.layer.cornerRadius = 24
        backgroundView.layoutMargins = UIEdgeInsets(hMargin: 40, vMargin: 32)

        backgroundView.addSubview(qrCodePaddingView)
        backgroundView.addSubview(usernameLabel)

        qrCodePaddingView.autoPinEdges(toSuperviewMarginsExcludingEdge: .bottom)

        qrCodePaddingView.autoPinEdge(.bottom, to: .top, of: usernameLabel, withOffset: -16)

        usernameLabel.autoPinEdges(toSuperviewMarginsExcludingEdge: .top)

        return backgroundView
    }

    private func buildColorOptionsView() -> UIView {
        let colorOptionButtons: [Usernames.QRCodeColor: ColorOptionButton] = {
            return Usernames.QRCodeColor.allCases.reduce(into: [:]) { partial, color in
                let button = ColorOptionButton(
                    size: 56,
                    color: color.background,
                    selected: color == currentColor
                ) { [weak self] in
                    self?.didSelectColor(color: color)
                }

                partial[color] = button
            }
        }()

        func stack(colors: [Usernames.QRCodeColor]) -> UIStackView {
            let stack = UIStackView(arrangedSubviews: colors.map { color in
                return colorOptionButtons[color]!
            })

            stack.layoutMargins = .zero
            stack.axis = .horizontal
            stack.alignment = .center
            stack.distribution = .equalSpacing

            return stack
        }

        let topStack = stack(colors: [.blue, .white, .grey, .olive])
        let bottomStack = stack(colors: [.green, .orange, .pink, .purple])

        let view = UIView()
        view.addSubview(topStack)
        view.addSubview(bottomStack)

        topStack.autoPinEdges(toSuperviewEdgesExcludingEdge: .bottom)
        topStack.autoPinEdge(.bottom, to: .top, of: bottomStack, withOffset: -26)
        bottomStack.autoPinEdges(toSuperviewEdgesExcludingEdge: .top)

        return view
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didTapCancel),
            accessibilityIdentifier: "cancel"
        )

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(didTapDone),
            accessibilityIdentifier: "done"
        )

        navigationItem.title = OWSLocalizedString(
            "USERNAME_LINK_QR_CODE_COLOR_PICKER_VIEW_TITLE_COLOR",
            comment: "A title for a view that allows you to pick a color for a QR code for your username link."
        )

        buildTableContents()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        colorPickerDelegate?.didDismissPresentedSheet()
    }

    private func buildTableContents() {
        let section = OWSTableSection(items: [
            .itemWrappingView(
                viewBlock: { [weak self] in
                    guard let self else { return nil }

                    let qrCodeView = self.buildQRCodeView()

                    // The QR code view has a fixed width, so wrap it in a view
                    // that can stretch.
                    let wrapper = UIView()
                    wrapper.addSubview(qrCodeView)

                    qrCodeView.autoPinEdge(toSuperviewEdge: .top)
                    qrCodeView.autoPinEdge(toSuperviewEdge: .bottom)
                    qrCodeView.autoHCenterInSuperview()

                    return wrapper
                },
                margins: UIEdgeInsets(top: 20, leading: 32, bottom: 24, trailing: 32)
            ),
            .itemWrappingView(
                viewBlock: { [weak self] in
                    self?.buildColorOptionsView()
                },
                margins: UIEdgeInsets(top: 24, leading: 36, bottom: 16, trailing: 36)
            )
        ])

        section.hasBackground = false
        section.hasSeparators = false

        contents = OWSTableContents(sections: [section])
    }

    private func reloadTableContents() {
        self.tableView.reloadData()
    }

    // MARK: - Events

    @objc
    private func didTapCancel() {
        dismiss(animated: true)
    }

    @objc
    private func didTapDone() {
        if startingColor != currentColor {
            colorPickerDelegate?.didFinalizeSelectedColor(color: currentColor)
        }

        dismiss(animated: true)
    }

    private func didSelectColor(color selectedColor: Usernames.QRCodeColor) {
        currentColor = selectedColor
        reloadTableContents()
    }
}

// MARK: - ColorOptionButton

private extension UsernameLinkQRCodeColorPickerViewController {
    /// Represents a single color that can be selected by the user.
    class ColorOptionButton: UIButton {
        private let size: CGFloat
        private let color: UIColor

        private let onTap: () -> Void

        init(
            size: CGFloat,
            color: UIColor,
            selected: Bool,
            onTap: @escaping () -> Void
        ) {
            self.size = size
            self.color = color
            self.onTap = onTap

            super.init(frame: .zero)

            setImage(selected: selected)

            adjustsImageWhenHighlighted = false
            autoPinToSquareAspectRatio()
            autoSetDimension(.width, toSize: size)

            addTarget(self, action: #selector(didTap), for: .touchUpInside)
        }

        required init?(coder: NSCoder) { owsFail("Not implemented!") }

        override var frame: CGRect {
            didSet { layer.cornerRadius = width / 2 }
        }

        private func setImage(selected: Bool) {
            let image: UIImage = {
                if selected {
                    return Self.drawSelectedImage(
                        color: color.cgColor,
                        outerCircleColor: Theme.isDarkThemeEnabled ? .white : .black,
                        size: .square(size)
                    )
                } else {
                    return Self.drawUnselectedImage(
                        color: color.cgColor,
                        size: .square(size)
                    )
                }
            }()

            setImage(image, for: .normal)
        }

        @objc
        private func didTap() {
            onTap()
        }

        // MARK: Image drawing

        /// A colored circle with a dimmed border.
        private static func drawUnselectedImage(
            color: CGColor,
            size: CGSize
        ) -> UIImage {
            return UIGraphicsImageRenderer(size: size).image { uiContext in
                drawColoredCircleWithBorder(
                    cgContext: uiContext.cgContext,
                    color: color,
                    rect: CGRect(origin: .zero, size: size)
                )
            }
        }

        /// A colored circle with a dimmed border, inset within an outer circle.
        private static func drawSelectedImage(
            color: CGColor,
            outerCircleColor: CGColor,
            size: CGSize
        ) -> UIImage {
            return UIGraphicsImageRenderer(size: size).image { uiContext in
                let rect = CGRect(origin: .zero, size: size)

                let cgContext = uiContext.cgContext

                cgContext.setStrokeColor(outerCircleColor)
                cgContext.strokeEllipse(fittingIn: rect, width: 3)

                drawColoredCircleWithBorder(
                    cgContext: cgContext,
                    color: color,
                    rect: rect.inset(by: UIEdgeInsets(margin: 7))
                )
            }
        }

        /// Draw a colored circle with a border into the given rect in the given
        /// context.
        private static func drawColoredCircleWithBorder(
            cgContext: CGContext,
            color: CGColor,
            rect: CGRect
        ) {
            cgContext.setFillColor(color)
            cgContext.fillEllipse(in: rect)

            cgContext.setStrokeColor(.black_alpha12)
            cgContext.strokeEllipse(fittingIn: rect, width: 2)
        }
    }
}

private extension CGContext {
    func strokeEllipse(fittingIn rect: CGRect, width: CGFloat) {
        setLineWidth(width)
        strokeEllipse(in: rect.inset(by: width / 2))
    }
}

private extension CGRect {
    func inset(by amount: CGFloat) -> CGRect {
        return insetBy(dx: amount, dy: amount)
    }
}

private extension CGColor {
    static let white: CGColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let black: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let black_alpha12 = CGColor(red: 0, green: 0, blue: 0, alpha: 0.12)
}
