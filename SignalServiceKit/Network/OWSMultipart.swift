//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

struct OWSMultipartTextPart {
    let key: String
    let value: String
}

/// Based on AFNetworking's AFURLRequestSerialization.
enum OWSMultipartBody {
    static func createMultipartFormBoundary() -> String {
        String(format: "Boundary+%016llX", CUnsignedLongLong.random(in: .min ... .max))
    }

    static func write(inputFile: URL, outputFile: URL, name: String, fileName: String, mimeType: String, boundary: String, textParts: any Sequence<OWSMultipartTextPart>) throws {
        guard outputFile.isFileURL else {
            throw urlErrorNotAFileUrl
        }

        // TODO: Audit streamStatus
        guard let outputStream = OutputStream(url: outputFile, append: false) else {
            throw urlErrorUnreachable
        }
        let outputStreamDelegate = OWSMultipartStreamDelegate()
        outputStream.delegate = outputStreamDelegate
        outputStream.schedule(in: .current, forMode: .default)
        outputStream.open()

        guard outputStream.streamStatus == .open else {
            throw urlErrorUnreachable
        }

        do {
            defer {
                outputStream.remove(from: .current, forMode: .default)
                outputStream.close()
            }

            var isFirstPart = true
            for textPart in textParts {
                try write(textPart, boundary: boundary, initialBoundary: isFirstPart, finalBoundary: false, outputStream: outputStream)
                isFirstPart = false
            }

            try writeBodyPart(inputFile: inputFile, name: name, fileName: fileName, mimeType: mimeType, boundary: boundary, initialBoundary: isFirstPart, finalBoundary: true, outputStream: outputStream)
        }

        guard outputStream.streamStatus == .closed && !outputStreamDelegate.hadError else {
            throw URLError(.badURL)
        }
    }

    private static func writeBodyPart(inputFile: URL, name: String, fileName: String, mimeType: String, boundary: String, initialBoundary: Bool, finalBoundary: Bool, outputStream: OutputStream) throws {
        let startingBoundary = initialBoundary ? AFMultipartForm.initialBoundary(boundary) : AFMultipartForm.encapsulationBoundary(boundary)
        try write(Data(startingBoundary.utf8), outputStream: outputStream)

        let headers = stringForHeaders(headersForBody(name: name, fileName: fileName, mimeType: mimeType))
        try write(Data(headers.utf8), outputStream: outputStream)

        try write(inputFile: inputFile, outputStream: outputStream)

        let endingBoundary = finalBoundary ? AFMultipartForm.finalBoundary(boundary) : ""
        try write(Data(endingBoundary.utf8), outputStream: outputStream)
    }

    private static func write(inputFile: URL, outputStream: OutputStream) throws {
        guard inputFile.isFileURL else {
            throw urlErrorNotAFileUrl
        }
        guard try inputFile.checkResourceIsReachable() else {
            throw urlErrorUnreachable
        }

        guard let inputStream = InputStream(url: inputFile) else {
            throw urlErrorUnreachable
        }
        let inputStreamDelegate = OWSMultipartStreamDelegate()
        inputStream.delegate = inputStreamDelegate
        inputStream.schedule(in: .current, forMode: .default)
        inputStream.open()
        guard inputStream.streamStatus == .open else {
            throw urlErrorUnreachable
        }

        do {
            defer {
                inputStream.remove(from: .current, forMode: .default)
                inputStream.close()
            }

            try write(inputStream, outputStream: outputStream)
        }

        guard inputStream.streamStatus == .closed && !inputStreamDelegate.hadError else {
            throw URLError(.badURL)
        }
    }

    private static func write(_ inputStream: InputStream, outputStream: OutputStream) throws {
        var buffer = Data(count: 8192)
        while inputStream.hasBytesAvailable {
            guard outputStream.hasSpaceAvailable else {
                throw URLError(.badURL)
            }

            let numberOfBytesRead = buffer.withUnsafeMutableBytes {
                inputStream.read($0.baseAddress!, maxLength: $0.count)
            }
            if numberOfBytesRead < 0 {
                throw URLError(.badURL)
            }
            if numberOfBytesRead == 0 {
                return
            }

            try write(buffer.prefix(numberOfBytesRead), outputStream: outputStream)
        }
    }

    /// Assumes `textPart`'s key and value are safe strings to place into a multi-part form without further escaping.
    private static func write(_ textPart: OWSMultipartTextPart, boundary: String, initialBoundary: Bool, finalBoundary: Bool, outputStream: OutputStream) throws {
        owsPrecondition(!textPart.value.isEmpty)
        owsPrecondition(!textPart.key.isEmpty)

        let startingBoundary = initialBoundary ? AFMultipartForm.initialBoundary(boundary) : AFMultipartForm.encapsulationBoundary(boundary)
        try write(Data(startingBoundary.utf8), outputStream: outputStream)

        let headersString = stringForHeaders([
            "Content-Disposition": "form-data; name=\"\(textPart.key)\""
        ])
        try write(Data(headersString.utf8), outputStream: outputStream)

        try write(Data(textPart.value.utf8), outputStream: outputStream)

        let endingBoundary = finalBoundary ? AFMultipartForm.finalBoundary(boundary) : ""
        try write(Data(endingBoundary.utf8), outputStream: outputStream)
    }

    private static func write(_ data: Data, outputStream: OutputStream) throws {
        var dataToWrite = data
        while !dataToWrite.isEmpty {
            let bytesWritten = dataToWrite.withUnsafeBytes { bufferPtr in
                outputStream.write(bufferPtr.baseAddress!, maxLength: bufferPtr.count)
            }
            if bytesWritten < 1 {
                throw URLError(.badURL)
            }
            dataToWrite = dataToWrite.dropFirst(bytesWritten)
        }
    }

    private static func headersForBody(name: String, fileName: String, mimeType: String) -> KeyValuePairs<String, String> {
        [
            "Content-Disposition": "form-data; name=\"\(name)\"; filename=\"\(fileName)\"",
            "Content-Type": mimeType,
        ]
    }

    /// This function assumes the keys and values are safe character sets for use in headers and does no escaping.
    private static func stringForHeaders(_ headers: any Sequence<(key: String, value: String)>) -> String {
        var result = String()
        for (field, value) in headers {
            result += "\(field): \(value)\r\n"
        }
        result += "\r\n"
        return result
    }

    private static let urlErrorNotAFileUrl = URLError(.badURL, userInfo: [NSLocalizedFailureReasonErrorKey: NSLocalizedString("Expected URL to be a file URL", tableName: "AFNetworking", comment: "")])
    private static let urlErrorUnreachable = URLError(.badURL, userInfo: [NSLocalizedFailureReasonErrorKey: NSLocalizedString("File URL not reachable.", tableName: "AFNetworking", comment: "")])
}

private class OWSMultipartStreamDelegate: NSObject, StreamDelegate {
    @Atomic var hadError = false

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        if eventCode == .errorOccurred {
            hadError = true
        }
    }
}

private enum AFMultipartForm {
    @inlinable
    static func initialBoundary(_ boundary: String) -> String {
        "--\(boundary)\r\n"
    }

    @inlinable
    static func encapsulationBoundary(_ boundary: String) -> String {
        "\r\n--\(boundary)\r\n"
    }

    @inlinable
    static func finalBoundary(_ boundary: String) -> String {
        "\r\n--\(boundary)--\r\n"
    }
}
