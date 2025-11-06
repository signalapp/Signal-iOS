//
//  SecurityManager.swift
//  EMMA Security Kit
//
//  Swift API for EMMA security features
//

import Foundation

// MARK: - Threat Category

public enum ThreatCategory: String, CaseIterable {
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
    case critical = "CRITICAL"
    case nuclear = "NUCLEAR"

    init(threatLevel: Float) {
        switch threatLevel {
        case 0.0..<0.35:
            self = .low
        case 0.35..<0.65:
            self = .medium
        case 0.65..<0.85:
            self = .high
        case 0.85..<0.95:
            self = .critical
        default:
            self = .nuclear
        }
    }

    public var chaosIntensity: Int {
        switch self {
        case .low: return 10
        case .medium: return 60
        case .high: return 100
        case .critical: return 150
        case .nuclear: return 200
        }
    }

    public var colorHex: String {
        switch self {
        case .low: return "00FF88"
        case .medium: return "FFB800"
        case .high: return "FF6B00"
        case .critical: return "FF3B30"
        case .nuclear: return "FF006B"
        }
    }
}

// MARK: - Threat Analysis (Swift)

public struct ThreatAnalysis {
    public let threatLevel: Float
    public let hypervisorConfidence: Float
    public let timingAnomalyDetected: Bool
    public let cacheAnomalyDetected: Bool
    public let perfCounterBlocked: Bool
    public let memoryAnomalyDetected: Bool
    public let analysisTimestamp: UInt64

    public var category: ThreatCategory {
        return ThreatCategory(threatLevel: threatLevel)
    }

    public var chaosIntensity: Int {
        return category.chaosIntensity
    }

    init(from objcAnalysis: EMThreatAnalysis) {
        self.threatLevel = objcAnalysis.threatLevel
        self.hypervisorConfidence = objcAnalysis.hypervisorConfidence
        self.timingAnomalyDetected = objcAnalysis.timingAnomalyDetected
        self.cacheAnomalyDetected = objcAnalysis.cacheAnomalyDetected
        self.perfCounterBlocked = objcAnalysis.perfCounterBlocked
        self.memoryAnomalyDetected = objcAnalysis.memoryAnomalyDetected
        self.analysisTimestamp = objcAnalysis.analysisTimestamp
    }
}

// MARK: - Security Manager

public class SecurityManager {

    // Singleton instance
    public static let shared = SecurityManager()

    private let detector = EMEL2Detector.shared()
    private var monitoringTimer: Timer?
    private var currentAnalysis: ThreatAnalysis?

    // Configuration
    public var monitoringInterval: TimeInterval = 5.0 // Check every 5 seconds
    public var isMonitoring: Bool = false

    // Callbacks
    public var onThreatLevelChanged: ((ThreatAnalysis) -> Void)?
    public var onHighThreatDetected: ((ThreatAnalysis) -> Void)?

    private init() {
        // Private initializer for singleton
    }

    // MARK: - Initialization

    public func initialize() -> Bool {
        let success = detector.initialize()
        if success {
            NSLog("[EMMA] Security Manager initialized")
        } else {
            NSLog("[EMMA] Failed to initialize Security Manager")
        }
        return success
    }

    // MARK: - Threat Analysis

    public func analyzeThreat() -> ThreatAnalysis? {
        guard let objcAnalysis = detector.analyzeThreat() else {
            return nil
        }

        let analysis = ThreatAnalysis(from: objcAnalysis)
        currentAnalysis = analysis

        // Trigger callbacks
        onThreatLevelChanged?(analysis)

        if analysis.threatLevel > 0.65 {
            onHighThreatDetected?(analysis)
        }

        return analysis
    }

    public var latestAnalysis: ThreatAnalysis? {
        return currentAnalysis
    }

    // MARK: - Monitoring

    public func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true

        monitoringTimer = Timer.scheduledTimer(withTimeInterval: monitoringInterval, repeats: true) { [weak self] _ in
            self?.analyzeThreat()
        }

        NSLog("[EMMA] Security monitoring started")
    }

    public func stopMonitoring() {
        guard isMonitoring else { return }

        monitoringTimer?.invalidate()
        monitoringTimer = nil
        isMonitoring = false

        NSLog("[EMMA] Security monitoring stopped")
    }

    // MARK: - Countermeasures

    public func activateCountermeasures(intensity: Int) {
        NSLog("[EMMA] Activating countermeasures with intensity: %d", intensity)

        // Poison cache based on intensity
        let cacheIntensity = min(100, intensity / 2)
        EMCacheOperations.poisonCacheIntensityPercent(Int32(cacheIntensity))

        // Add timing noise
        let timingIntensity = min(100, intensity / 2)
        EMTimingObfuscation.addTimingNoiseIntensityPercent(Int32(timingIntensity))

        // Fill RAM if intensity is very high
        if intensity > 150 {
            let ramFillPercent = min(80, (intensity - 150) / 2)
            EMMemoryScrambler.fillAvailableRAMWithPercent(Int32(ramFillPercent))
        }

        // Create decoy patterns for extreme threats
        if intensity >= 200 {
            EMMemoryScrambler.createDecoyPatternsWithSizeMB(100)
        }
    }

    // MARK: - Memory Protection

    public func secureWipe(data: inout Data) {
        var mutableData = NSMutableData(data: data)
        EMMemoryScrambler.secureWipeData(mutableData)
        data = mutableData as Data
    }

    public func scrambleMemory(data: inout Data) {
        var mutableData = NSMutableData(data: data)
        EMMemoryScrambler.scrambleData(mutableData)
        data = mutableData as Data
    }

    // MARK: - Timing Obfuscation

    public func executeWithObfuscation(chaosPercent: Int, block: @escaping () -> Void) {
        EMTimingObfuscation.executeWithObfuscation(block, chaosPercent: Int32(chaosPercent))
    }

    public func randomDelay(minUs: Int, maxUs: Int) {
        EMTimingObfuscation.randomDelayMinUs(Int32(minUs), maxUs: Int32(maxUs))
    }
}

// MARK: - Post-Quantum Cryptography

public struct KyberKeyPair {
    public let publicKey: Data
    public let secretKey: Data
}

public struct KyberEncapsulationResult {
    public let ciphertext: Data
    public let sharedSecret: Data
}

public class PostQuantumCrypto {

    // Generate Kyber-1024 keypair
    public static func generateKeyPair() -> KyberKeyPair? {
        guard let objcKeyPair = EMKyber1024.generateKeypair() else {
            return nil
        }

        return KyberKeyPair(
            publicKey: objcKeyPair.publicKey,
            secretKey: objcKeyPair.secretKey
        )
    }

    // Encapsulate shared secret
    public static func encapsulate(publicKey: Data) -> KyberEncapsulationResult? {
        guard let objcResult = EMKyber1024.encapsulate(withPublicKey: publicKey) else {
            return nil
        }

        return KyberEncapsulationResult(
            ciphertext: objcResult.ciphertext,
            sharedSecret: objcResult.sharedSecret
        )
    }

    // Decapsulate shared secret
    public static func decapsulate(ciphertext: Data, secretKey: Data) -> Data? {
        return EMKyber1024.decapsulate(withCiphertext: ciphertext, secretKey: secretKey)
    }
}
