
internal func SNLog(_ message: String) {
    #if DEBUG
    print("[Session] \(message)")
    #endif
}
