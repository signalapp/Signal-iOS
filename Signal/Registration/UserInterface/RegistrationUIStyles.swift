//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SwiftUI

extension Registration {

    enum UI {

        private static func primaryButtonStyle() -> some PrimitiveButtonStyle {
#if compiler(>=6.2)
            if #available(iOS 26, *) {
                return GlassProminentButtonStyle.glassProminent
            } else {
                return BorderedProminentButtonStyle.borderedProminent
            }
#else
            return BorderedProminentButtonStyle.borderedProminent
#endif
        }

        private static func secondaryButtonStyle() -> some PrimitiveButtonStyle {
#if compiler(>=6.2)
            if #available(iOS 26, *) {
                return GlassProminentButtonStyle.glassProminent
            } else {
                return PlainButtonStyle.plain
            }
#else
            return PlainButtonStyle.plain
#endif
        }

        private static var largeButtonContentPadding: EdgeInsets {
            // SwiftUI wants there to be 7pt smaller than NSDirectionalEdgeInsets.largeButtonContentInsets
            // in order to achieve exactly the same button size.
            EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)
        }

        private static var mediumButtonContentPadding: EdgeInsets {
            // SwiftUI wants there to be 7pt smaller than NSDirectionalEdgeInsets.mediumButtonContentInsets
            // in order to achieve exactly the same button size.
            EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)
        }

        private static func buttonBorderShape() -> ButtonBorderShape {
            if #available(iOS 26, *) {
                return ButtonBorderShape.capsule
            } else {
                return ButtonBorderShape.roundedRectangle(radius: 14)
            }
        }

        private static func primaryButtonForegroundColor() -> Color {
            return .white
        }

        private static func secondaryButtonForegroundColor() -> Color {
            if #available(iOS 26, *) {
                return .Signal.label
            } else {
                return .Signal.accent
            }
        }

        struct LargePrimaryButtonStyle: PrimitiveButtonStyle {
            @ViewBuilder
            func makeBody(configuration: Configuration) -> some View {
                Button(action: configuration.trigger) {
                    HStack {
                        Spacer()
                        configuration.label
                            .font(.headline)
                            .foregroundColor(UI.primaryButtonForegroundColor())
                        Spacer()
                    }
                    .padding(UI.largeButtonContentPadding)
                }
                .buttonStyle(UI.primaryButtonStyle())
                .buttonBorderShape(UI.buttonBorderShape())
                .tint(Color.Signal.accent)
            }
        }

        struct LargeSecondaryButtonStyle: PrimitiveButtonStyle {
            @ViewBuilder
            func makeBody(configuration: Configuration) -> some View {
                Button(action: configuration.trigger) {
                    HStack {
                        Spacer()
                        configuration.label
                            .font(.headline)
                            .foregroundColor(UI.secondaryButtonForegroundColor())
                        Spacer()
                    }
                    .padding(UI.largeButtonContentPadding)
                }
                .buttonStyle(UI.secondaryButtonStyle())
                .buttonBorderShape(UI.buttonBorderShape())
                .tint(.clear)
            }
        }

        struct MediumSecondaryButtonStyle: PrimitiveButtonStyle {
            @ViewBuilder
            func makeBody(configuration: Configuration) -> some View {
                Button(action: configuration.trigger) {
                    configuration.label
                        .font(.headline)
                        .foregroundColor(UI.secondaryButtonForegroundColor())
                        .padding(UI.mediumButtonContentPadding)
                }
                .buttonStyle(UI.secondaryButtonStyle())
                .buttonBorderShape(UI.buttonBorderShape())
                .tint(.clear)
            }
        }
    }
}
