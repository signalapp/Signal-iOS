//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SwiftUI

struct LinearProgressView<Progress: BinaryFloatingPoint>: View {
    var progress: Progress

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .foregroundStyle(Color.Signal.secondaryFill)

                Capsule()
                    .foregroundStyle(Color.Signal.accent)
                    .frame(width: geo.size.width * CGFloat(progress))
            }
        }
        .frame(height: 4)
        .frame(maxWidth: 360)
    }
}

@available(iOS 17, *)
#Preview {
    @Previewable @State var progress: Float = 0.0
    LinearProgressView(progress: progress)
        // Add this if you want your animation to look the same as the preview
        .animation(.smooth, value: progress)
        // Simulate progress
        .task { @MainActor in
            while progress < 1 {
                progress += 0.011
                try? await Task.sleep(nanoseconds: 60 * NSEC_PER_MSEC)
            }
        }
}
