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

final class AppIconSettingsTableViewController: OWSTableViewController2 {

    // MARK: Static properties

    private static let customIcons: [[AppIcon]] = [
        [.default, .white, .color, .night],
        [.nightVariant, .chat, .bubbles, .yellow],
        [.news, .notes, .weather, .waves],
    ]

    /// This URL itself is not used. The action is overridden in the text view delegate function.
    private static let learnMoreURL = URL(string: "https://support.signal.org/")!

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
        
        // Create SwiftUI view
        let swiftUIView = AppIconSettingsView(
            didChangeIcon: { [weak self] in
                self?.iconDelegate?.didChangeIcon()
            },
            onLearnMoreTapped: { [weak self] in
                self?.didTapLearnMore()
            }
        )
        self.swiftUIView = swiftUIView
        
        let hostingController = UIHostingController(rootView: swiftUIView)
        hostingController.view.backgroundColor = .clear
        
        section.add(.init(customCellBlock: { [weak self] in
            guard let self else { return UITableViewCell() }
            
            let cell = OWSTableItem.newCell()

            let hostView = hostingController.view!
            hostView.translatesAutoresizingMaskIntoConstraints = false

            if hostingController.parent == nil {
                self.addChild(hostingController)
            cell.contentView.addSubview(hostingController.view)
            hostingController.didMove(toParent: self)
            }

            if hostView.superview == nil {
                cell.contentView.addSubview(hostView)
                hostView.autoPinEdgesToSuperviewMargins(
                with: .init(hMargin: -Self.cellHInnerMargin, vMargin: 24)
               )
            }
            
            return cell
        }))
        
        section.footerAttributedTitle = NSAttributedString.composed(of: [
            OWSLocalizedString(
                "SETTINGS_APP_ICON_FOOTER",
                comment: "The footer for the app icon selection settings page.",
            ),
            "\n",
            CommonStrings.learnMore.styled(with: .link(Self.learnMoreURL)),
        ])
        .styled(with: defaultFooterTextStyle)
        section.footerTextViewDelegate = self
        section.shouldDisableCellSelection = true

        contents.add(section)
        self.contents = contents
    }

    private func didTapLearnMore() {
        let learnMoreViewController = AppIconLearnMoreTableViewController()
        let navigationController = OWSNavigationController(rootViewController: learnMoreViewController)
        presentFormSheet(navigationController, animated: true)
    }
}

// MARK: UITextViewDelegate

extension AppIconSettingsTableViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith url: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
        if url == Self.learnMoreURL {
            didTapLearnMore()
        }
        return false
    }
}

// MARK: - SwiftUI View

struct AppIconSettingsView: View {
    @State private var currentIcon = UIApplication.shared.currentAppIcon
    @State private var isAnimating = false
    @State private var iconSize = CGFloat(60)
    
    let customIcons: [[AppIcon]] = [
        [.default, .white, .color, .night],
        [.nightVariant, .chat, .bubbles, .yellow],
        [.news, .notes, .weather, .waves],
    ]
    
    let didChangeIcon: () -> Void
    let onLearnMoreTapped: () -> Void
    
    var body: some View {
        VStack{
                iconGrid
            }
            .onAppear {
                updateIconSize()
            }
            .onChange(of: geo.size) { _ in
                updateIconSize()
            }
            .background(
                GeometryReader { geo in
                   Color.clear.onAppear{ updateIconSize() }.onChange(of: geo.size) {
                        _ in updateIconSize()
                   } 
                }
            )
    }
    
    private var iconGrid: some View {
        VStack(spacing: 32) {
            ForEach(0..<customIcons.count, id: \.self) { rowIndex in
                HStack(spacing: 0) {
                    Spacer()
                    
                    ForEach(0..<customIcons[rowIndex].count, id: \.self) { colIndex in
                        let icon = customIcons[rowIndex][colIndex]
                        IconButtonView(
                            icon: icon,
                            isSelected: currentIcon == icon,
                            scale: isAnimating && currentIcon == icon ? 0.8 : 1.0,
                            borderWidth: isAnimating && currentIcon == icon ? 3 : 0,
                            iconSize: iconSize,
                            action: {
                                didTapIcon(icon)
                            }
                        )
                        .accessibilityLabel(Text(icon.accessibilityLabel))
                        .accessibilityAddTraits(currentIcon == icon ? .isSelected : [])
                    }
                    
                    Spacer()
                }
                .frame(height: iconSize)
            }
        }
    }
    
    private func updateIconSize() {
        let isiOS26 = if #available(iOS 26.0, *) { true } else { false }
        iconSize = switch (
            UIDevice.current.isNarrowerThanIPhone6,
            UIDevice.current.isPlusSizePhone,
            isiOS26,
        ) {
        case (true, _, false): 56
        case (true, _, true): 61.5
        case (_, true, false): 64
        case (_, true, true): 68
        case (_, _, false): 60
        case (_, _, true): 64
        }
    }
    
    private func didTapIcon(_ icon: AppIcon) {
        guard currentIcon != icon else { return }
        
        currentIcon = icon
        
        UIApplication.shared.setAlternateIconName(icon.alternateIconName) { [weak self] error in
            guard let self else { return }
            DispatchQueue.main.async{
                if let error = error {
                    owsFailDebug("Failed to set alternate icon: \(error)")
                }
                self.didChangeIcon()
            }
        }
        
        animateSelection()
    }
    
    private func animateSelection() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
            isAnimating = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                isAnimating = false
            }
        }
    }
}

// MARK: - Icon Button View

struct IconButtonView: View {
    let icon: AppIcon
    let isSelected: Bool
    let scale: CGFloat
    let borderWidth: CGFloat
    let iconSize: CGFloat
    let action: () -> Void
    
    var borderColor: Color {
        Theme.isDarkThemeEnabled ? Color(uiColor: .ows_gray05) : Color(uiColor: .ows_black)
    }
    
    var body: some View {
        Button(action: action) {
            Image(uiImage: UIImage(resource: icon.previewImageResource))
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .scaleEffect(scale)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
        }
    }
    
    private var cornerRadius: CGFloat {
        let radius = iconSize * 0.24 * (4 / 3)
        return radius
    }
}
