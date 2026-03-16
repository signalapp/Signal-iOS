//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

protocol AppIconSettingsTableViewControllerDelegate: AnyObject {
    func didChangeIcon()
}

// MARK: - SwiftUI View

struct AppIconSettingsView: View {
    @State private var currentIcon = UIApplication.shared.currentAppIcon
    @State private var showLearnMore = false
    var onIconChanged: (() -> Void)?

    private static let customIcons: [[AppIcon]] = [
        [.default, .white, .color, .night],
        [.nightVariant, .chat, .bubbles, .yellow],
        [.news, .notes, .weather, .waves],
    ]

    var body: some View {
        Form {
            Section {
                IconSelectionGridView(currentIcon: $currentIcon, onIconChanged: onIconChanged)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(OWSLocalizedString(
                        "SETTINGS_APP_ICON_FOOTER",
                        comment: "The footer for the app icon selection settings page."
                    ))
                    Button(action: { showLearnMore = true }) {
                        Text(CommonStrings.learnMore)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .navigationTitle(OWSLocalizedString(
            "SETTINGS_APP_ICON_TITLE",
            comment: "The title for the app icon selection settings page."
        ))
        .sheet(isPresented: $showLearnMore) {
            AppIconLearnMoreWrapper()
        }
    }
}

// MARK: - Icon Grid View

struct IconSelectionGridView: View {
    @Binding var currentIcon: AppIcon?
    var onIconChanged: (() -> Void)?

    private static let customIcons: [[AppIcon]] = [
        [.default, .white, .color, .night],
        [.nightVariant, .chat, .bubbles, .yellow],
        [.news, .notes, .weather, .waves],
    ]

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass

    var body: some View {
        VStack(spacing: 32) {
            ForEach(Array(Self.customIcons.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    Spacer()
                    ForEach(row, id: \.self) { icon in
                        IconButtonView(
                            icon: icon,
                            iconSize: calculateIconSize(),
                            isSelected: currentIcon == icon,
                            action: {
                                selectIcon(icon)
                            }
                        )
                    }
                    Spacer()
                }
                .frame(height: calculateIconSize())
            }
        }
        .padding(.vertical, 24)
    }

    private func calculateIconSize() -> CGFloat {
        let isiOS26 = if #available(iOS 26.0, *) { true } else { false }
        let isNarrow = UIDevice.current.isNarrowerThanIPhone6
        let isPlus = UIDevice.current.isPlusSizePhone

        return switch (isNarrow, isPlus, isiOS26) {
        case (true, _, false): 56
        case (true, _, true): 61.5
        case (_, true, false): 64
        case (_, true, true): 68
        case (_, _, false): 60
        case (_, _, true): 64
        }
    }

    private func selectIcon(_ icon: AppIcon) {
        guard currentIcon != icon else { return }

        UIApplication.shared.setAlternateIconName(icon.alternateIconName) { error in
            if let error {
                owsFailDebug("Failed to update app icon: \(error)")
            }
        }

        withAnimation(.spring(response: 0.15, dampingFraction: 1, blendDuration: 0)) {
            currentIcon = icon
        }
        onIconChanged?()
    }
}

// MARK: - Icon Button

struct IconButtonView: View {
    let icon: AppIcon
    let iconSize: CGFloat
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            Image(uiImage: UIImage(resource: icon.previewImageResource))
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .scaleEffect(isSelected ? 0.8 : 1.0)
        }
        .frame(width: iconSize, height: iconSize)
        .background(
            RoundedRectangle(cornerRadius: iconSize * 0.24 * (4 / 3), style: .continuous)
                .stroke(
                    borderColor,
                    lineWidth: isSelected ? 3 : 0
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color(UIColor.ows_gray05) : Color(UIColor.ows_black)
    }
}

// MARK: - Learn More Wrapper

struct AppIconLearnMoreWrapper: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let learnMoreViewController = AppIconLearnMoreTableViewController()
        return OWSNavigationController(rootViewController: learnMoreViewController)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
}

// MARK: - UIKit Bridge

final class AppIconSettingsTableViewController: OWSTableViewController2 {

    // MARK: Properties

    weak var iconDelegate: AppIconSettingsTableViewControllerDelegate?

    // MARK: View lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = OWSLocalizedString(
            "SETTINGS_APP_ICON_TITLE",
            comment: "The title for the app icon selection settings page.",
        )
        updateTableContents()
    }

    override func themeDidChange() {
        super.themeDidChange()
        updateTableContents()
    }

    // MARK: Table setup

    private func updateTableContents() {
        let contents = OWSTableContents()

        let section = OWSTableSection()
        section.add(.init(customCellBlock: { [weak self] in
            guard let self else { return UITableViewCell() }
            return self.buildSwiftUICell()
        }))
        section.footerAttributedTitle = NSAttributedString.composed(of: [
            OWSLocalizedString(
                "SETTINGS_APP_ICON_FOOTER",
                comment: "The footer for the app icon selection settings page.",
            ),
            "\n",
            CommonStrings.learnMore.styled(with: .link(URL(string: "https://support.signal.org/")!)),
        ])
        .styled(with: defaultFooterTextStyle)
        section.footerTextViewDelegate = self
        section.shouldDisableCellSelection = true

        contents.add(section)
        self.contents = contents
    }

    private func buildSwiftUICell() -> UITableViewCell {
        let hostingView = IconSelectionGridView(
            currentIcon: .constant(UIApplication.shared.currentAppIcon),
            onIconChanged: { [weak self] in
                self?.iconDelegate?.didChangeIcon()
            }
        )

        let hostingController = UIHostingController(rootView: hostingView)
        let cell = UITableViewCell()
        cell.contentView.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: cell.contentView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor),
            hostingController.view.leftAnchor.constraint(equalTo: cell.contentView.leftAnchor),
            hostingController.view.rightAnchor.constraint(equalTo: cell.contentView.rightAnchor),
        ])
        cell.selectionStyle = .none
        hostingController.view.backgroundColor = UIColor.clear
        hostingController.view.isOpaque = false
        
        return cell
    }
}

// MARK: UITextViewDelegate

extension AppIconSettingsTableViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        if url.absoluteString == "https://support.signal.org/" {
            let learnMoreViewController = AppIconLearnMoreTableViewController()
            let navigationController = OWSNavigationController(rootViewController: learnMoreViewController)
            presentFormSheet(navigationController, animated: true)
        }
        return false
    }
}
