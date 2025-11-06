//
//  ThreatIndicator.swift
//  SWORDCOMM SecurityKit UI
//
//  Visual threat level indicator widget
//

import SwiftUI

/// Animated threat level indicator with color-coded visualization
@available(iOS 15.0, *)
public struct ThreatIndicator: View {
    let level: Double // 0.0 to 1.0
    let size: CGFloat
    @State private var isAnimating: Bool = false

    public init(level: Double, size: CGFloat = 48) {
        self.level = level
        self.size = size
    }

    private var color: Color {
        if level < 0.3 {
            return .green
        } else if level < 0.5 {
            return .yellow
        } else if level < 0.7 {
            return .orange
        } else {
            return .red
        }
    }

    private var icon: String {
        if level < 0.3 {
            return "checkmark.shield.fill"
        } else if level < 0.5 {
            return "exclamationmark.shield"
        } else if level < 0.7 {
            return "exclamationmark.triangle.fill"
        } else {
            return "xmark.shield.fill"
        }
    }

    public var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: size, height: size)

            // Animated ring for high threats
            if level > 0.7 {
                Circle()
                    .stroke(color, lineWidth: 3)
                    .frame(width: size - 4, height: size - 4)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .opacity(isAnimating ? 0.0 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 1.0)
                            .repeatForever(autoreverses: false),
                        value: isAnimating
                    )
            }

            // Icon
            Image(systemName: icon)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundColor(color)
                .scaleEffect(level > 0.7 && isAnimating ? 1.1 : 1.0)
                .animation(
                    level > 0.7 ?
                        Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true) : nil,
                    value: isAnimating
                )
        }
        .onAppear {
            if level > 0.7 {
                isAnimating = true
            }
        }
        .onChange(of: level) { newLevel in
            isAnimating = newLevel > 0.7
        }
    }
}

/// Compact linear threat indicator (progress bar style)
@available(iOS 15.0, *)
public struct LinearThreatIndicator: View {
    let level: Double // 0.0 to 1.0
    let height: CGFloat

    public init(level: Double, height: CGFloat = 8) {
        self.level = level
        self.height = height
    }

    private var color: Color {
        if level < 0.3 {
            return .green
        } else if level < 0.5 {
            return .yellow
        } else if level < 0.7 {
            return .orange
        } else {
            return .red
        }
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: height)

                // Filled portion
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(colors: [color.opacity(0.7), color]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * CGFloat(level), height: height)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: level)
            }
        }
        .frame(height: height)
    }
}

/// Segmented threat indicator (discrete levels)
@available(iOS 15.0, *)
public struct SegmentedThreatIndicator: View {
    let level: Double // 0.0 to 1.0
    let segments: Int
    let spacing: CGFloat

    public init(level: Double, segments: Int = 5, spacing: CGFloat = 4) {
        self.level = level
        self.segments = segments
        self.spacing = spacing
    }

    private func colorForSegment(_ index: Int) -> Color {
        let segmentLevel = Double(index + 1) / Double(segments)

        if segmentLevel < 0.3 {
            return .green
        } else if segmentLevel < 0.5 {
            return .yellow
        } else if segmentLevel < 0.7 {
            return .orange
        } else {
            return .red
        }
    }

    private func isSegmentFilled(_ index: Int) -> Bool {
        let segmentThreshold = Double(index + 1) / Double(segments)
        return level >= segmentThreshold
    }

    public var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<segments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSegmentFilled(index) ?
                          colorForSegment(index) :
                          Color.gray.opacity(0.2))
                    .frame(height: 24)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: level)
            }
        }
    }
}

// MARK: - Preview

@available(iOS 15.0, *)
struct ThreatIndicator_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 32) {
            // Circular indicators
            HStack(spacing: 20) {
                VStack {
                    ThreatIndicator(level: 0.1, size: 48)
                    Text("Secure")
                        .font(.caption)
                }

                VStack {
                    ThreatIndicator(level: 0.4, size: 48)
                    Text("Low")
                        .font(.caption)
                }

                VStack {
                    ThreatIndicator(level: 0.6, size: 48)
                    Text("Moderate")
                        .font(.caption)
                }

                VStack {
                    ThreatIndicator(level: 0.9, size: 48)
                    Text("High")
                        .font(.caption)
                }
            }

            Divider()

            // Linear indicators
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Low Threat")
                        .font(.caption)
                    LinearThreatIndicator(level: 0.2)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Moderate Threat")
                        .font(.caption)
                    LinearThreatIndicator(level: 0.6)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("High Threat")
                        .font(.caption)
                    LinearThreatIndicator(level: 0.9)
                }
            }
            .padding(.horizontal)

            Divider()

            // Segmented indicators
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1 of 5 segments")
                        .font(.caption)
                    SegmentedThreatIndicator(level: 0.15)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("3 of 5 segments")
                        .font(.caption)
                    SegmentedThreatIndicator(level: 0.55)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("5 of 5 segments")
                        .font(.caption)
                    SegmentedThreatIndicator(level: 1.0)
                }
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
        .background(Color(UIColor.systemGroupedBackground))
    }
}
