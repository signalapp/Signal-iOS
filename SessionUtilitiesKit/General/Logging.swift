import SignalCoreKit

public func SNLog(_ message: String) {
    #if DEBUG
    print("[Session] \(message)")
    #endif
    OWSLogger.info("[Session] \(message)")
}
