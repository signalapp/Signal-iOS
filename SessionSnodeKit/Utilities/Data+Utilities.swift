import Foundation

internal extension Data {

    /// Returns `size` bytes of random data generated using the default secure random number generator. See
    /// [SecRandomCopyBytes](https://developer.apple.com/documentation/security/1399291-secrandomcopybytes) for more information.
    static func getSecureRandomData(ofSize size: UInt) -> Data? {
        var data = Data(count: Int(size))
        let result = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, Int(size), $0.baseAddress!) }
        guard result == errSecSuccess else { return nil }
        return data
    }

    init(from inputStream: InputStream) throws {
        self.init()
        inputStream.open()
        defer { inputStream.close() }
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while inputStream.hasBytesAvailable {
            let count = inputStream.read(buffer, maxLength: bufferSize)
            if count < 0 {
                throw inputStream.streamError!
            } else if count == 0 {
                break
            } else {
                append(buffer, count: count)
            }
        }
    }
}
