//
//  SWORDCOMMSettingsView.swift
//  SWORDCOMM Settings Panel
//
//  Comprehensive settings view for SWORDCOMM security and translation features
//

import SwiftUI

/// Main SWORDCOMM settings panel for integration into Signal Settings
@available(iOS 15.0, *)
public struct SWORDCOMMSettingsView: View {
    @StateObject private var viewModel = SWORDCOMMSettingsViewModel()

    public init() {}

    public var body: some View {
        Form {
            // Security section
            Section(header: Text("Security Features")) {
                // Security monitoring toggle
                Toggle("Enable Security Monitoring", isOn: $viewModel.securityMonitoringEnabled)
                    .onChange(of: viewModel.securityMonitoringEnabled) { enabled in
                        viewModel.toggleSecurityMonitoring(enabled)
                    }

                if viewModel.securityMonitoringEnabled {
                    // Threat display
                    NavigationLink(destination: SecurityDashboardView()) {
                        HStack {
                            ThreatIndicator(level: viewModel.currentThreatLevel, size: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Security Status")
                                    .font(.system(size: 15))

                                Text(viewModel.securityStatusText)
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                    }

                    // Auto-countermeasures
                    Toggle("Auto-activate countermeasures", isOn: $viewModel.autoCountermeasuresEnabled)

                    // Countermeasure intensity
                    if viewModel.autoCountermeasuresEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Countermeasure Intensity")
                                    .font(.system(size: 15))

                                Spacer()

                                Text("\(Int(viewModel.countermeasureIntensity * 100))%")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }

                            Slider(value: $viewModel.countermeasureIntensity, in: 0.0...1.0)
                                .accentColor(.orange)
                        }
                    }
                }
            }

            // Translation section
            Section(header: Text("Translation Features")) {
                // Translation toggle
                Toggle("Enable Translation", isOn: $viewModel.translationEnabled)

                if viewModel.translationEnabled {
                    // Auto-translate
                    Toggle("Auto-translate messages", isOn: $viewModel.autoTranslateEnabled)

                    // Network fallback
                    Toggle("Use network fallback", isOn: $viewModel.networkFallbackEnabled)
                        .disabled(!viewModel.autoTranslateEnabled)

                    // Language preferences
                    NavigationLink(destination: TranslationSettingsView()) {
                        HStack {
                            Text("Language Preferences")

                            Spacer()

                            Text("\(viewModel.sourceLanguage) → \(viewModel.targetLanguage)")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Model status
                    HStack {
                        Text("On-device model")

                        Spacer()

                        if viewModel.isModelLoaded {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Loaded")
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.orange)
                                Text("Not loaded")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .font(.system(size: 15))
                }
            }

            // Post-Quantum Cryptography section
            Section(header: Text("Post-Quantum Cryptography")) {
                // PQC status
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NIST PQC Compliant")
                            .font(.system(size: 15))

                        Text("ML-KEM-1024 + ML-DSA-87 + AES-256-GCM")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 20))
                }

                // Show details
                NavigationLink(destination: PQCComplianceView()) {
                    Text("View Compliance Details")
                }
            }

            // Advanced settings
            Section(header: Text("Advanced")) {
                // Security HUD
                Toggle("Show Security HUD", isOn: $viewModel.showSecurityHUD)

                // Performance monitoring
                Toggle("Performance monitoring", isOn: $viewModel.performanceMonitoringEnabled)

                // Debug mode
                if viewModel.isDebugBuild {
                    Toggle("Debug mode", isOn: $viewModel.debugModeEnabled)
                }

                // Reset button
                Button(action: {
                    viewModel.resetToDefaults()
                }) {
                    Text("Reset to Defaults")
                        .foregroundColor(.red)
                }
            }

            // About section
            Section(header: Text("About")) {
                HStack {
                    Text("SWORDCOMM Version")
                    Spacer()
                    Text(viewModel.swordcommVersion)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Security Level")
                    Spacer()
                    Text("NIST Level 5")
                        .foregroundColor(.secondary)
                }

                NavigationLink(destination: AboutSWORDCOMMView()) {
                    Text("About SWORDCOMM")
                }
            }
        }
        .navigationTitle("SWORDCOMM")
        .onAppear {
            viewModel.loadSettings()
        }
    }
}

// MARK: - View Model

@available(iOS 15.0, *)
@MainActor
class SWORDCOMMSettingsViewModel: ObservableObject {
    // Security settings
    @Published var securityMonitoringEnabled: Bool = true
    @Published var autoCountermeasuresEnabled: Bool = false
    @Published var countermeasureIntensity: Double = 0.5
    @Published var currentThreatLevel: Double = 0.0
    @Published var securityStatusText: String = "Initializing..."

    // Translation settings
    @Published var translationEnabled: Bool = true
    @Published var autoTranslateEnabled: Bool = false
    @Published var networkFallbackEnabled: Bool = true
    @Published var sourceLanguage: String = "da"
    @Published var targetLanguage: String = "en"
    @Published var isModelLoaded: Bool = false

    // UI settings
    @Published var showSecurityHUD: Bool = false
    @Published var performanceMonitoringEnabled: Bool = true

    // Debug settings
    @Published var debugModeEnabled: Bool = false
    @Published var isDebugBuild: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    // Version info
    let emmaVersion: String = "1.2.0-nist-compliant"

    private let securityManager = SecurityManager.shared
    private let translationEngine = EMTranslationEngine.shared()
    private var monitoringTimer: Timer?

    func loadSettings() {
        // Load from UserDefaults or configuration
        let defaults = UserDefaults.standard

        securityMonitoringEnabled = defaults.bool(forKey: "SWORDCOMM.SecurityMonitoring") != false // Default true
        autoCountermeasuresEnabled = defaults.bool(forKey: "SWORDCOMM.AutoCountermeasures")
        countermeasureIntensity = defaults.double(forKey: "SWORDCOMM.CountermeasureIntensity") != 0 ?
            defaults.double(forKey: "SWORDCOMM.CountermeasureIntensity") : 0.5

        translationEnabled = defaults.bool(forKey: "SWORDCOMM.Translation") != false // Default true
        autoTranslateEnabled = defaults.bool(forKey: "SWORDCOMM.AutoTranslate")
        networkFallbackEnabled = defaults.bool(forKey: "SWORDCOMM.NetworkFallback") != false // Default true

        sourceLanguage = defaults.string(forKey: "SWORDCOMM.SourceLanguage") ?? "da"
        targetLanguage = defaults.string(forKey: "SWORDCOMM.TargetLanguage") ?? "en"

        showSecurityHUD = defaults.bool(forKey: "SWORDCOMM.ShowSecurityHUD")
        performanceMonitoringEnabled = defaults.bool(forKey: "SWORDCOMM.PerformanceMonitoring") != false

        // Check model status
        isModelLoaded = translationEngine.isModelLoaded()

        // Update security status
        updateSecurityStatus()

        // Start monitoring if enabled
        if securityMonitoringEnabled {
            startMonitoring()
        }
    }

    func saveSettings() {
        let defaults = UserDefaults.standard

        defaults.set(securityMonitoringEnabled, forKey: "SWORDCOMM.SecurityMonitoring")
        defaults.set(autoCountermeasuresEnabled, forKey: "SWORDCOMM.AutoCountermeasures")
        defaults.set(countermeasureIntensity, forKey: "SWORDCOMM.CountermeasureIntensity")

        defaults.set(translationEnabled, forKey: "SWORDCOMM.Translation")
        defaults.set(autoTranslateEnabled, forKey: "SWORDCOMM.AutoTranslate")
        defaults.set(networkFallbackEnabled, forKey: "SWORDCOMM.NetworkFallback")

        defaults.set(sourceLanguage, forKey: "SWORDCOMM.SourceLanguage")
        defaults.set(targetLanguage, forKey: "SWORDCOMM.TargetLanguage")

        defaults.set(showSecurityHUD, forKey: "SWORDCOMM.ShowSecurityHUD")
        defaults.set(performanceMonitoringEnabled, forKey: "SWORDCOMM.PerformanceMonitoring")
    }

    func toggleSecurityMonitoring(_ enabled: Bool) {
        if enabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }
        saveSettings()
    }

    func resetToDefaults() {
        securityMonitoringEnabled = true
        autoCountermeasuresEnabled = false
        countermeasureIntensity = 0.5

        translationEnabled = true
        autoTranslateEnabled = false
        networkFallbackEnabled = true

        sourceLanguage = "da"
        targetLanguage = "en"

        showSecurityHUD = false
        performanceMonitoringEnabled = true

        saveSettings()
    }

    private func startMonitoring() {
        guard securityManager.initialize() else {
            securityStatusText = "Initialization failed"
            return
        }

        securityManager.startMonitoring()

        // Set up callbacks
        securityManager.onThreatLevelChanged = { [weak self] analysis in
            Task { @MainActor in
                self?.updateFromAnalysis(analysis)
            }
        }

        // Start periodic updates
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateSecurityStatus()
            }
        }

        updateSecurityStatus()
    }

    private func stopMonitoring() {
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        securityManager.stopMonitoring()
    }

    private func updateSecurityStatus() {
        guard let analysis = securityManager.analyzeThreat() else {
            securityStatusText = "No data"
            return
        }

        updateFromAnalysis(analysis)
    }

    private func updateFromAnalysis(_ analysis: ThreatAnalysis) {
        currentThreatLevel = analysis.threatLevel

        if currentThreatLevel < 0.3 {
            securityStatusText = "Secure"
        } else if currentThreatLevel < 0.5 {
            securityStatusText = "Low threat detected"
        } else if currentThreatLevel < 0.7 {
            securityStatusText = "Moderate threat"
        } else {
            securityStatusText = "High threat!"
        }

        // Auto-activate countermeasures if enabled
        if autoCountermeasuresEnabled && currentThreatLevel > 0.65 {
            securityManager.activateCountermeasures(intensity: countermeasureIntensity)
        }
    }
}

// MARK: - Security Dashboard View

@available(iOS 15.0, *)
struct SecurityDashboardView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Security HUD
                SecurityHUD()
                    .padding(.horizontal)

                Spacer()
            }
            .padding(.vertical)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("Security Dashboard")
    }
}

// MARK: - PQC Compliance View

@available(iOS 15.0, *)
struct PQCComplianceView: View {
    var body: some View {
        Form {
            Section(header: Text("NIST Standards")) {
                ComplianceRow(
                    name: "ML-KEM-1024",
                    standard: "FIPS 203",
                    status: .compliant
                )

                ComplianceRow(
                    name: "ML-DSA-87",
                    standard: "FIPS 204",
                    status: .compliant
                )

                ComplianceRow(
                    name: "AES-256-GCM",
                    standard: "FIPS 197",
                    status: .compliant
                )

                ComplianceRow(
                    name: "HMAC-SHA256",
                    standard: "FIPS 198-1",
                    status: .compliant
                )
            }

            Section(header: Text("Key Sizes")) {
                KeySizeRow(name: "ML-KEM-1024 Public Key", size: 1568)
                KeySizeRow(name: "ML-KEM-1024 Secret Key", size: 3168)
                KeySizeRow(name: "ML-DSA-87 Public Key", size: 2592)
                KeySizeRow(name: "ML-DSA-87 Secret Key", size: 4896)
                KeySizeRow(name: "AES Encryption Key", size: 32)
            }

            Section(header: Text("Security Level")) {
                HStack {
                    Text("NIST Security Level")
                    Spacer()
                    Text("5 (Highest)")
                        .foregroundColor(.green)
                        .fontWeight(.semibold)
                }

                HStack {
                    Text("Quantum Resistance")
                    Spacer()
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                }

                HStack {
                    Text("Classical Security")
                    Spacer()
                    Text("256-bit equivalent")
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Documentation")) {
                Link(destination: URL(string: "https://csrc.nist.gov/pubs/fips/203/final")!) {
                    HStack {
                        Text("FIPS 203 (ML-KEM)")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12))
                    }
                }

                Link(destination: URL(string: "https://csrc.nist.gov/pubs/fips/204/final")!) {
                    HStack {
                        Text("FIPS 204 (ML-DSA)")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12))
                    }
                }
            }
        }
        .navigationTitle("PQC Compliance")
    }
}

private struct ComplianceRow: View {
    enum Status {
        case compliant
        case partial
        case notCompliant
    }

    let name: String
    let standard: String
    let status: Status

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 15))

                Text(standard)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            Spacer()

            statusBadge
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .compliant:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Compliant")
                    .foregroundColor(.green)
                    .font(.system(size: 13, weight: .semibold))
            }
        case .partial:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
                Text("Partial")
                    .foregroundColor(.orange)
                    .font(.system(size: 13, weight: .semibold))
            }
        case .notCompliant:
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("Not Compliant")
                    .foregroundColor(.red)
                    .font(.system(size: 13, weight: .semibold))
            }
        }
    }
}

private struct KeySizeRow: View {
    let name: String
    let size: Int

    var body: some View {
        HStack {
            Text(name)
                .font(.system(size: 15))

            Spacer()

            Text("\(size) bytes")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - About SWORDCOMM View

@available(iOS 15.0, *)
struct AboutSWORDCOMMView: View {
    var body: some View {
        Form {
            Section(header: Text("SWORDCOMM")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Secure Worldwide Operations Enterprise Messaging Military-grade Android Real-time Data Communication (iOS Port)")
                        .font(.system(size: 15))

                    Text("Advanced security and translation features for Signal")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }

            Section(header: Text("Features")) {
                FeatureRow(icon: "shield.checkered", name: "Hypervisor Detection", description: "iOS jailbreak and security threat detection")
                FeatureRow(icon: "lock.shield", name: "Post-Quantum Crypto", description: "NIST-compliant ML-KEM & ML-DSA")
                FeatureRow(icon: "character.bubble", name: "Translation", description: "On-device Danish-English translation")
                FeatureRow(icon: "timer", name: "Timing Obfuscation", description: "Side-channel attack mitigation")
            }

            Section(header: Text("Credits")) {
                Text("Developed by SWORD Intelligence")
                    .font(.system(size: 15))

                Text("Based on SWORDCOMM-Android")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("About SWORDCOMM")
    }
}

private struct FeatureRow: View {
    let icon: String
    let name: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 15, weight: .medium))

                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

@available(iOS 15.0, *)
struct SWORDCOMMSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SWORDCOMMSettingsView()
        }
    }
}
