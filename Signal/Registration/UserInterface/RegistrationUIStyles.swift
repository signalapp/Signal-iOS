//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SwiftUI
import SignalServiceKit

extension Registration {
    enum UI {
        struct FilledButtonStyle: PrimitiveButtonStyle {
            func makeBody(configuration: Configuration) -> some View {
                Button(action: configuration.trigger) {
                    HStack {
                        Spacer()
                        configuration.label
                            .colorScheme(.dark)
                            .font(.headline)
                        Spacer()
                    }
                    .frame(minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.Signal.ultramarine)
            }
        }

        struct BorderlessButtonStyle: PrimitiveButtonStyle {
            func makeBody(configuration: Configuration) -> some View {
                Button(action: configuration.trigger) {
                    HStack {
                        Spacer()
                        configuration.label
                            .colorScheme(.light)
                            .font(.headline)
                        Spacer()
                    }
                    .frame(minHeight: 32)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}
