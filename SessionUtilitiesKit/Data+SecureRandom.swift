import Foundation

public extension Data {

    /// Returns `size` bytes of random data generated using the default secure random number generator. See
    /// [SecRandomCopyBytes](https://developer.apple.com/documentation/security/1399291-secrandomcopybytes) for more information.
    static func getSecureRandomData(ofSize size: UInt) -> Data? {
        var data = Data(count: Int(size))
        let result = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, Int(size), $0.baseAddress!) }
        guard result == errSecSuccess else { return nil }
        return data
    }
}
