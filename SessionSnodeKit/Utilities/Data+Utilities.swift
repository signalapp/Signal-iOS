import Foundation

public extension Data {

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
