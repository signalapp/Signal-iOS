//
//  SecurityHUD.swift
//  EMMA SecurityKit UI
//
//  SwiftUI component for displaying real-time security status
//

import SwiftUI

/// Real-time security status display with threat visualization
@available(iOS 15.0, *)
public struct SecurityHUD: View {
    @StateObject private var viewModel = SecurityHUDViewModel()
    @State private var isExpanded: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Compact header (always visible)
            HStack(spacing: 12) {
                ThreatIndicator(
                    level: viewModel.threatLevel,
                    size: 32
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.statusText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(viewModel.statusColor)

                    if viewModel.isMonitoring {
                        Text("Monitoring active")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(UIColor.systemBackground))

            // Expanded details
            if isExpanded {
                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    // Threat metrics
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Threat Analysis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        MetricRow(
                            label: "Threat Level",
                            value: String(format: "%.1f%%", viewModel.threatLevel * 100),
                            color: viewModel.statusColor
                        )

                        MetricRow(
                            label: "Hypervisor Confidence",
                            value: String(format: "%.1f%%", viewModel.hypervisorConfidence * 100),
                            color: viewModel.hypervisorConfidence > 0.5 ? .red : .green
                        )

                        MetricRow(
                            label: "Jailbreak Detection",
                            value: viewModel.isJailbroken ? "DETECTED" : "Clean",
                            color: viewModel.isJailbroken ? .red : .green
                        )
                    }

                    Divider()

                    // Performance metrics
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Performance Counters")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        MetricRow(
                            label: "Memory Usage",
                            value: viewModel.memoryUsage,
                            color: .blue
                        )

                        MetricRow(
                            label: "CPU Time",
                            value: viewModel.cpuTime,
                            color: .blue
                        )
                    }

                    Divider()

                    // Countermeasures
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Active Countermeasures")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        if viewModel.countermeasuresActive {
                            HStack(spacing: 8) {
                                Image(systemName: "shield.checkered")
                                    .font(.system(size: 14))
                                    .foregroundColor(.orange)

                                Text("Timing obfuscation active")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }

                            HStack(spacing: 8) {
                                Image(systemName: "lock.shield")
                                    .font(.system(size: 14))
                                    .foregroundColor(.orange)

                                Text("Cache poisoning enabled")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("No active countermeasures")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Action buttons
                    HStack(spacing: 12) {
                        Button(action: {
                            viewModel.refreshAnalysis()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                Text("Refresh")
                            }
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .cornerRadius(8)
                        }

                        if viewModel.threatLevel > 0.5 {
                            Button(action: {
                                viewModel.activateCountermeasures()
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "shield.lefthalf.filled")
                                    Text("Activate Defense")
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.orange)
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color(UIColor.secondarySystemBackground))
            }
        }
        .background(Color(UIColor.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        .onAppear {
            viewModel.startMonitoring()
        }
        .onDisappear {
            viewModel.stopMonitoring()
        }
    }
}

// MARK: - Metric Row Component

@available(iOS 15.0, *)
private struct MetricRow: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(color)
        }
    }
}

// MARK: - View Model

@available(iOS 15.0, *)
@MainActor
class SecurityHUDViewModel: ObservableObject {
    @Published var threatLevel: Double = 0.0
    @Published var hypervisorConfidence: Double = 0.0
    @Published var isJailbroken: Bool = false
    @Published var statusText: String = "Initializing..."
    @Published var statusColor: Color = .gray
    @Published var isMonitoring: Bool = false
    @Published var countermeasuresActive: Bool = false
    @Published var memoryUsage: String = "0 MB"
    @Published var cpuTime: String = "0 ms"

    private var monitoringTimer: Timer?
    private let securityManager = SecurityManager.shared

    init() {
        updateStatus()
    }

    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true

        // Initialize security manager
        if securityManager.initialize() {
            NSLog("[EMMA] SecurityHUD: Security manager initialized")
            securityManager.startMonitoring()

            // Set up callbacks
            securityManager.onThreatLevelChanged = { [weak self] analysis in
                Task { @MainActor in
                    self?.updateFromAnalysis(analysis)
                }
            }

            securityManager.onHighThreatDetected = { [weak self] analysis in
                Task { @MainActor in
                    self?.handleHighThreat(analysis)
                }
            }
        }

        // Start periodic updates (every 2 seconds)
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateStatus()
            }
        }

        updateStatus()
    }

    func stopMonitoring() {
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        securityManager.stopMonitoring()
    }

    func refreshAnalysis() {
        updateStatus()
    }

    func activateCountermeasures() {
        guard let analysis = securityManager.analyzeThreat() else { return }

        securityManager.activateCountermeasures(intensity: analysis.chaosIntensity)
        countermeasuresActive = true

        // Auto-deactivate after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.countermeasuresActive = false
        }
    }

    private func updateStatus() {
        guard let analysis = securityManager.analyzeThreat() else {
            statusText = "No data"
            statusColor = .gray
            return
        }

        updateFromAnalysis(analysis)
    }

    private func updateFromAnalysis(_ analysis: ThreatAnalysis) {
        threatLevel = analysis.threatLevel
        hypervisorConfidence = analysis.hypervisorConfidence
        isJailbroken = analysis.threatLevel > 0.65

        // Update status text based on threat level
        if threatLevel < 0.3 {
            statusText = "Secure"
            statusColor = .green
        } else if threatLevel < 0.5 {
            statusText = "Low Threat"
            statusColor = .yellow
        } else if threatLevel < 0.7 {
            statusText = "Moderate Threat"
            statusColor = .orange
        } else {
            statusText = "High Threat"
            statusColor = .red
        }

        // Update performance metrics
        if let counters = securityManager.getPerformanceCounters() {
            let memoryMB = Double(counters.residentMemoryBytes) / (1024.0 * 1024.0)
            memoryUsage = String(format: "%.1f MB", memoryMB)

            let cpuMs = Double(counters.cpuTimeNs) / 1_000_000.0
            cpuTime = String(format: "%.2f ms", cpuMs)
        }
    }

    private func handleHighThreat(_ analysis: ThreatAnalysis) {
        // Show alert or notification
        NSLog("[EMMA] HIGH THREAT DETECTED! Level: \(analysis.threatLevel)")

        // Optionally auto-activate countermeasures
        if analysis.threatLevel > 0.8 {
            activateCountermeasures()
        }
    }
}

// MARK: - Preview

@available(iOS 15.0, *)
struct SecurityHUD_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            SecurityHUD()
                .padding()

            Spacer()
        }
        .background(Color(UIColor.systemGroupedBackground))
    }
}
