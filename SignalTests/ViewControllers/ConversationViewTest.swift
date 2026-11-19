//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal
@testable import SignalServiceKit
@testable import SignalUI

class ConversationViewTest: SignalBaseTest {
    func testConversationStyleComparison() throws {
        let thread = ContactThreadFactory().create()

        Theme.setIsDarkThemeEnabledForTests(false)
        XCTAssertFalse(Theme.isDarkThemeEnabled)

        let style1 = ConversationStyle(
            type: .`default`,
            thread: thread,
            viewWidth: 100,
            hasWallpaper: false,
            shouldDimWallpaperInDarkMode: false,
            chatColor: ChatColorSettingStore.Constants.defaultColor.colorSetting,
        )
        let style2 = ConversationStyle(
            type: .`default`,
            thread: thread,
            viewWidth: 100,
            hasWallpaper: false,
            shouldDimWallpaperInDarkMode: false,
            chatColor: ChatColorSettingStore.Constants.defaultColor.colorSetting,
        )
        let style3 = ConversationStyle(
            type: .`default`,
            thread: thread,
            viewWidth: 101,
            hasWallpaper: false,
            shouldDimWallpaperInDarkMode: false,
            chatColor: ChatColorSettingStore.Constants.defaultColor.colorSetting,
        )

        XCTAssertFalse(style1.isDarkThemeEnabled)
        XCTAssertFalse(style2.isDarkThemeEnabled)
        XCTAssertFalse(style3.isDarkThemeEnabled)

        XCTAssertTrue(style1 == style2)
        XCTAssertFalse(style1 == style3)
        XCTAssertFalse(style2 == style3)

        Theme.setIsDarkThemeEnabledForTests(true)
        XCTAssertTrue(Theme.isDarkThemeEnabled)

        let style4 = ConversationStyle(
            type: .`default`,
            thread: thread,
            viewWidth: 100,
            hasWallpaper: false,
            shouldDimWallpaperInDarkMode: false,
            chatColor: ChatColorSettingStore.Constants.defaultColor.colorSetting,
        )

        XCTAssertFalse(style1.isDarkThemeEnabled)
        XCTAssertFalse(style2.isDarkThemeEnabled)
        XCTAssertFalse(style3.isDarkThemeEnabled)
        XCTAssertTrue(style4.isDarkThemeEnabled)

        XCTAssertTrue(style1 == style2)
        XCTAssertFalse(style1 == style3)
        XCTAssertFalse(style2 == style3)

        XCTAssertFalse(style4 == style1)
        XCTAssertFalse(style4 == style2)
        XCTAssertFalse(style4 == style3)
    }
}

extension ConversationViewTest: MockConversationDelegate {
    var mockConversationViewWidth: CGFloat { 320 }

    @MainActor
    func testInlineTimestampPreservesBodyTextBottomInset() throws {
        let wasDarkThemeEnabled = Theme.isDarkThemeEnabled
        Theme.setIsDarkThemeEnabledForTests(false)
        defer { Theme.setIsDarkThemeEnabledForTests(wasDarkThemeEnabled) }
        write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx,
            )
        }
        for category: UIContentSizeCategory in [
            .extraSmall,
            .small,
            .medium,
            .large,
            .extraLarge,
            .extraExtraLarge,
            .extraExtraExtraLarge,
            .accessibilityMedium,
            .accessibilityLarge,
            .accessibilityExtraLarge,
            .accessibilityExtraExtraLarge,
            .accessibilityExtraExtraExtraLarge,
        ] {
            UITraitCollection(preferredContentSizeCategory: category).performAsCurrent {
                do {
                    try checkInlineTimestampLayout()
                } catch {
                    XCTFail("\(category.rawValue): \(error)")
                }
            }
        }
    }

    @MainActor
    private func checkInlineTimestampLayout() throws {
        let thread = ContactThreadFactory().create()
        let style = ConversationStyle(
            type: .default,
            thread: thread,
            viewWidth: mockConversationViewWidth,
            hasWallpaper: false,
            shouldDimWallpaperInDarkMode: false,
            chatColor: ChatColorSettingStore.Constants.defaultColor.colorSetting,
        )
        for text in ["안녕하세요", "Okay sure", "gyp", "첫째 줄\n마지막 줄", "مرحبا", "Hello 👋"] {
            let preview = MockConversationView(
                model: .init(items: [.incoming(text: text), .outgoing(text: text)]),
                hasWallpaper: false,
                customChatColor: nil,
            )
            preview.delegate = self
            preview.frame = CGRect(x: 0, y: 0, width: mockConversationViewWidth, height: 1000)
            preview.frame.size.height = preview.systemLayoutSizeFitting(
                CGSize(width: mockConversationViewWidth, height: 0),
                withHorizontalFittingPriority: .required,
                verticalFittingPriority: .fittingSizeLevel,
            ).height
            preview.layoutIfNeeded()

            func descendants(of view: UIView) -> [UIView] {
                view.subviews.flatMap { [$0] + descendants(of: $0) }
            }
            let stacks = descendants(of: preview).filter {
                $0.accessibilityLabel == "message.bottomNestedTextStackView"
            }
            XCTAssertEqual(stacks.count, 2, text)
            for stack in stacks {
                let body = try XCTUnwrap(descendants(of: stack).first { $0.accessibilityLabel == "bodyText" })
                let bodyFrame = body.convert(body.bounds, to: stack)
                let footer = try XCTUnwrap(descendants(of: stack).first { $0.accessibilityLabel == "footer.outerStack" })
                let footerFrame = footer.convert(footer.bounds, to: stack)
                if footerFrame.minY >= bodyFrame.maxY {
                    XCTAssertGreaterThanOrEqual(stack.bounds.maxY, footerFrame.maxY, text)
                    continue
                }
                XCTAssertEqual(
                    stack.bounds.maxY - bodyFrame.maxY,
                    style.textInsetBottomBelowBodyText,
                    accuracy: 0.5,
                    text,
                )
                let timestampLabel = try XCTUnwrap(descendants(of: footer).compactMap { $0 as? UILabel }.first)
                let baselineContainer = UIView(frame: timestampLabel.bounds)
                let referenceLabel = UILabel()
                referenceLabel.font = timestampLabel.font
                referenceLabel.text = timestampLabel.text
                referenceLabel.translatesAutoresizingMaskIntoConstraints = false
                baselineContainer.addSubview(referenceLabel)
                let baselineProbe = UIView()
                baselineProbe.translatesAutoresizingMaskIntoConstraints = false
                baselineContainer.addSubview(baselineProbe)
                NSLayoutConstraint.activate([
                    referenceLabel.topAnchor.constraint(equalTo: baselineContainer.topAnchor),
                    referenceLabel.leadingAnchor.constraint(equalTo: baselineContainer.leadingAnchor),
                    referenceLabel.widthAnchor.constraint(equalToConstant: timestampLabel.bounds.size.width),
                    referenceLabel.heightAnchor.constraint(equalToConstant: timestampLabel.bounds.size.height),
                    baselineProbe.topAnchor.constraint(equalTo: referenceLabel.lastBaselineAnchor),
                    baselineProbe.leadingAnchor.constraint(equalTo: baselineContainer.leadingAnchor),
                    baselineProbe.widthAnchor.constraint(equalToConstant: 0),
                    baselineProbe.heightAnchor.constraint(equalToConstant: 0),
                ])
                baselineContainer.layoutIfNeeded()
                let config = CVTextLabel.Config(
                    text: .text(text),
                    displayConfig: .forUnstyledText(font: .dynamicTypeBody, textColor: .black),
                    font: .dynamicTypeBody,
                    textColor: .black,
                    selectionStyling: [:],
                    textAlignment: .natural,
                    lineBreakMode: .byWordWrapping,
                    numberOfLines: 0,
                    cacheKey: text,
                    items: [],
                    linkifyStyle: .underlined(bodyTextColor: .black),
                )
                let measurement = CVTextLabel.measureSize(config: config, maxWidth: bodyFrame.size.width)
                let bodyBaseline = bodyFrame.minY + (try XCTUnwrap(measurement.lastLineBaseline))
                let timestampBaseline = timestampLabel.convert(timestampLabel.bounds, to: stack).minY + baselineProbe.frame.minY
                XCTAssertEqual(timestampBaseline, bodyBaseline, accuracy: 1, text)
            }
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: preview.bounds).image { context in
                preview.layer.render(in: context.cgContext)
            })
            attachment.name = "Inline timestamp - \(UITraitCollection.current.preferredContentSizeCategory.rawValue) - \(text)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
