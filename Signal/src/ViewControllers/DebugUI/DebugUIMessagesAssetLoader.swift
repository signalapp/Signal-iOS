//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CoreGraphics
import LibSignalClient
import SignalServiceKit

#if USE_DEBUG_UI

enum DebugUIError: Error {
    case downloadFailed
    case imageGenerationFailed
    case fileCreationFailed
    case invalidMimeType
    case unknownFileExtension
}

class DebugUIMessagesAssetLoader {

    typealias Completion = (Result<Void, Error>) -> Void

    let filename: String
    let mimeType: String

    private(set) var prepare: ((@escaping Completion) -> Void)?

    private(set) var filePath: String?
    var labelEmoji: String { TSAttachment.emoji(forMimeType: mimeType) }

    // MARK: - Public

    static let jpegInstance: DebugUIMessagesAssetLoader = .fakeAssetLoaderWithUrl(
        "https://s3.amazonaws.com/ows-data/example_attachment_media/random-jpg.JPG",
        mimeType: OWSMimeTypeImageJpeg
    )
    static let gifInstance: DebugUIMessagesAssetLoader = .fakeAssetLoaderWithUrl(
        "https://s3.amazonaws.com/ows-data/example_attachment_media/random-gif.gif",
        mimeType: OWSMimeTypeImageGif
    )
    static let largeGifInstance: DebugUIMessagesAssetLoader = .fakeAssetLoaderWithUrl(
        "https://i.giphy.com/media/LTw0F3GAdaao8/source.gif",
        mimeType: OWSMimeTypeImageGif
    )
    static let mp3Instance: DebugUIMessagesAssetLoader = .fakeAssetLoaderWithUrl(
        "https://s3.amazonaws.com/ows-data/example_attachment_media/random-mp3.mp3",
        mimeType: "audio/mp3"
    )
    static let mp4Instance: DebugUIMessagesAssetLoader = .fakeAssetLoaderWithUrl(
        "https://s3.amazonaws.com/ows-data/example_attachment_media/random-mp4.mp4",
        mimeType: "video/mp4"
    )

    static let compactPortraitPngInstance: DebugUIMessagesAssetLoader = .fakePngAssetLoaderWithImageSize(
        .init(width: 60, height: 100),
        backgroundColor: .blue,
        textColor: .white,
        label: "P"
    )
    static let compactLandscapePngInstance: DebugUIMessagesAssetLoader = .fakePngAssetLoaderWithImageSize(
        .init(width: 100, height: 60),
        backgroundColor: .green,
        textColor: .white,
        label: "L"
    )
    static let tallPortraitPngInstance: DebugUIMessagesAssetLoader = .fakePngAssetLoaderWithImageSize(
        .init(width: 10, height: 100),
        backgroundColor: .yellow,
        textColor: .white,
        label: "P"
    )
    static let wideLandscapePngInstance: DebugUIMessagesAssetLoader = .fakePngAssetLoaderWithImageSize(
        .init(width: 100, height: 10),
        backgroundColor: .purple,
        textColor: .white,
        label: "L"
    )
    static let largePngInstance: DebugUIMessagesAssetLoader = .fakePngAssetLoaderWithImageSize(
        .square(4000),
        backgroundColor: .brown,
        textColor: .white,
        label: "B"
    )
    static let tinyPngInstance: DebugUIMessagesAssetLoader = .fakePngAssetLoaderWithImageSize(
        .square(2),
        backgroundColor: .cyan,
        textColor: .white,
        label: "T"
    )
    static func pngInstance(size: CGSize, backgroundColor: UIColor, textColor: UIColor, label: String) -> DebugUIMessagesAssetLoader {
        return .fakePngAssetLoaderWithImageSize(size, backgroundColor: backgroundColor, textColor: textColor, label: label)
    }
    static let mediumFilesizePngInstance: DebugUIMessagesAssetLoader = .fakeNoisePngAssetLoaderWithImageSize(1000)

    static let tinyPdfInstance: DebugUIMessagesAssetLoader = .fakeRandomAssetLoaderWithDataLength(256, mimeType: "application/pdf")!
    static let largePdfInstance: DebugUIMessagesAssetLoader = .fakeRandomAssetLoaderWithDataLength(4 * 1024 * 1024, mimeType: "application/pdf")!

    static let missingPngInstance: DebugUIMessagesAssetLoader = .fakeMissingAssetLoaderWithMimeType(OWSMimeTypeImagePng)!
    static let missingPdfInstance: DebugUIMessagesAssetLoader = .fakeMissingAssetLoaderWithMimeType("application/pdf")!
    static let oversizeTextInstance: DebugUIMessagesAssetLoader = .fakeOversizeTextAssetLoader(text: nil)
    static func oversizeTextInstance(text: String) -> DebugUIMessagesAssetLoader {
        return .fakeOversizeTextAssetLoader(text: text)
    }

    static func prepareAssetLoaders(
        _ assetLoaders: [DebugUIMessagesAssetLoader],
        completion: @escaping Completion
    ) {
        var promises = [AnyPromise]()

        assetLoaders.forEach { assetLoader in
            // Use chained promises to make the code more readable.
            let promise = AnyPromise { future in
                assetLoader.prepare!({ result in
                    switch result {
                    case .success:
                        future.resolve(value: Void())

                    case .failure(let error):
                        future.reject(error: error)
                    }
                })
            }
            promises.append(promise)
        }

        AnyPromise.when(resolved: promises)
            .done { _ in
                completion(.success(()))
            }.catch { error in
                completion(.failure(error))
            }
    }

    // MARK: - Private

    private init(filename: String, mimeType: String) {
        self.filename = filename
        self.mimeType = mimeType
    }

    // MARK: -

    private static func fakeAssetLoaderWithUrl(_ urlString: String, mimeType: String) -> DebugUIMessagesAssetLoader! {
        guard let url = URL(string: urlString), !mimeType.isEmpty else {
            return nil
        }
        let assetLoader = DebugUIMessagesAssetLoader(filename: url.lastPathComponent, mimeType: mimeType)
        assetLoader.prepare = { [weak assetLoader] completion in
            assetLoader?.ensureURLAssetLoaded(url, completion: completion)
        }
        return assetLoader
    }

    private func ensureURLAssetLoaded(_ url: URL, completion: @escaping Completion) {
        guard filePath == nil else {
            completion(.success(()))
            return
        }

        // Use a predictable file path so that we reuse the cache between app launches.
        let temporaryDirectory = OWSTemporaryDirectory()
        let cacheDirectory = temporaryDirectory.appendingPathComponent("cached_random_files")
        OWSFileSystem.ensureDirectoryExists(cacheDirectory)
        let filePath = cacheDirectory.appendingPathComponent(filename)
        guard !FileManager.default.fileExists(atPath: filePath) else {
            self.filePath = filePath
            completion(.success(()))
            return
        }

        let urlSession = OWSURLSession(securityPolicy: OWSURLSession.defaultSecurityPolicy, configuration: .ephemeral)
        urlSession.dataTaskPromise(url.absoluteString, method: .get)
            .done { response in
                guard let data = response.responseBodyData, data.count > 0 else {
                    owsFailDebug("Error write url response [\(url)]: \(filePath)")
                    completion(.failure(DebugUIError.downloadFailed))
                    return
                }
                do {
                    let fileUrl = URL(fileURLWithPath: filePath)
                    try data.write(to: fileUrl, options: .atomic)
                    owsAssertDebug(FileManager.default.fileExists(atPath: filePath))
                    completion(.success(()))
                } catch {
                    owsFailDebug("Error downloading [\(url)]: \(error)")
                    completion(.failure(error))
                }
            }
            .catch { error in
                owsFailDebug("Error downloading url[\(url)]: \(error)")
                completion(.failure(error))
            }

    }

    // MARK: -

    private static func fakePngAssetLoaderWithImageSize(
        _ imageSize: CGSize,
        backgroundColor: UIColor,
        textColor: UIColor,
        label: String
    ) -> DebugUIMessagesAssetLoader {
        owsAssertDebug(imageSize.isNonEmpty)
        owsAssertDebug(!label.isEmpty)

        let assetLoader = DebugUIMessagesAssetLoader(filename: "image.png", mimeType: OWSMimeTypeImagePng)
        assetLoader.prepare = { [weak assetLoader] completion in
            assetLoader?.ensurePngAssetLoaded(
                imageSize: imageSize,
                backgroundColor: backgroundColor,
                textColor: textColor,
                label: label,
                completion: completion
            )
        }
        return assetLoader
    }

    private func ensurePngAssetLoaded(
        imageSize: CGSize,
        backgroundColor: UIColor,
        textColor: UIColor,
        label: String,
        completion: Completion
    ) {
        owsAssertDebug(imageSize.isNonEmpty)
        owsAssertDebug(!label.isEmpty)

        guard filePath == nil else {
            completion(.success(()))
            return
        }

        let filePath = OWSFileSystem.temporaryFilePath(fileExtension: "png")
        guard
            let image = DebugUIMessagesAssetLoader.createRandomPngWithSize(
                imageSize,
                backgroundColor: backgroundColor,
                textColor: textColor,
                label: label),
            let pngData = image.pngData()
        else {
            completion(.failure(DebugUIError.imageGenerationFailed))
            return
        }

        do {
            try pngData.write(to: URL(fileURLWithPath: filePath), options: .atomic)
            self.filePath = filePath
            completion(.success(()))
        } catch {
            owsFailDebug("Error: \(error)")
            completion(.failure(error))
        }
    }

    private static func fakeNoisePngAssetLoaderWithImageSize(_ imageSize: UInt) -> DebugUIMessagesAssetLoader {
        owsAssertDebug(imageSize > 0)

        let assetLoader = DebugUIMessagesAssetLoader(filename: "image.png", mimeType: OWSMimeTypeImagePng)
        assetLoader.prepare = { [weak assetLoader] completion in
            assetLoader?.ensureNoisePngAssetLoaded(imageSize: imageSize, completion: completion)
        }
        return assetLoader
    }

    private func ensureNoisePngAssetLoaded(imageSize: UInt, completion: Completion) {
        owsAssertDebug(imageSize > 0)

        guard filePath == nil else {
            completion(.success(()))
            return
        }

        let filePath = OWSFileSystem.temporaryFilePath(fileExtension: "png")
        guard
            let image = DebugUIMessagesAssetLoader.buildNoiseImageWithSize(imageSize),
            let pngData = image.pngData()
        else {
            completion(.failure(DebugUIError.imageGenerationFailed))
            return
        }

        do {
            try pngData.write(to: URL(fileURLWithPath: filePath), options: .atomic)
            self.filePath = filePath
            completion(.success(()))
        } catch {
            owsFailDebug("Error: \(error)")
            completion(.failure(error))
        }
    }

    private static func buildNoiseImageWithSize(_ size: UInt) -> UIImage? {
        let backgroundColor = UIColor(rgbHex: 0xaca6633)
        return imageWithSize(size, backgroundColor: backgroundColor) { context in
            for x in 0..<size {
                for y in 0..<size {
                    let color = UIColor.ows_randomColor(isAlphaRandom: false)
                    context.setFillColor(color.cgColor)
                    let rect = CGRect(x: Int(x), y: Int(y), width: 1, height: 1)
                    context.fill([rect])
                }
            }
        }
    }

    private static func imageWithSize(
        _ imageSize: UInt,
        backgroundColor: UIColor,
        drawBlock: (CGContext) -> Void
    ) -> UIImage? {
        owsAssertDebug(imageSize > 0)

        let rect = CGRect(origin: .zero, size: .square(CGFloat(imageSize)))

        UIGraphicsBeginImageContextWithOptions(rect.size, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }

        context.setFillColor(backgroundColor.cgColor)
        context.fill([rect])

        context.saveGState()
        drawBlock(context)
        context.restoreGState()

        defer {
            UIGraphicsEndImageContext()
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()
        return image
    }

    private static func createRandomPngWithSize(
        _ imageSize: CGSize,
        backgroundColor: UIColor,
        textColor: UIColor,
        label: String
    ) -> UIImage? {
        owsAssertDebug(imageSize.isNonEmpty)
        owsAssertDebug(!label.isEmpty)

        let size = imageSize.applying(.scale(1 / UIScreen.main.scale)).roundedForScreenScale()

        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }

        let imageRect = CGRect(origin: .zero, size: size)

        context.setFillColor(backgroundColor.cgColor)
        context.fill([imageRect])

        let labelAsNSString = label as NSString
        let smallDimension = min(size.width, size.height)
        let font = UIFont.boldSystemFont(ofSize: smallDimension * 0.5)
        let textAttributes: [ NSAttributedString.Key: Any ] = [ .font: font, .foregroundColor: textColor ]
        var textRect = labelAsNSString.boundingRect(
            with: imageRect.size,
            options: [ .usesLineFragmentOrigin, .usesFontLeading ],
            attributes: textAttributes,
            context: nil
        )
        textRect.origin.x = 0.5 * (imageRect.width - textRect.width)
        textRect.origin.y = 0.5 * (imageRect.height - textRect.height)

        labelAsNSString.draw(at: textRect.origin, withAttributes: textAttributes)

        defer {
            UIGraphicsEndImageContext()
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()
        return image
    }

    // MARK: -

    private static func fakeRandomAssetLoaderWithDataLength(_ dataLength: UInt, mimeType: String) -> DebugUIMessagesAssetLoader? {
        owsAssertDebug(dataLength > 0)
        owsAssertDebug(!mimeType.isEmpty)

        guard let fileExtension = MIMETypeUtil.fileExtension(forMIMEType: mimeType) else {
            owsFailDebug("Invalid mime type: \(mimeType)")
            return nil
        }
        let assetLoader = DebugUIMessagesAssetLoader(filename: "attachment.\(fileExtension)", mimeType: mimeType)
        assetLoader.prepare = { [weak assetLoader] completion in
            assetLoader?.ensureRandomAssetLoaded(dataLength, completion: completion)
        }
        return assetLoader
    }

    private func ensureRandomAssetLoaded(_ dataLength: UInt, completion: Completion) {
        owsAssertDebug(dataLength > 0)

        guard filePath == nil else {
            completion(.success(()))
            return
        }

        guard let fileExtension = MIMETypeUtil.fileExtension(forMIMEType: mimeType) else {
            completion(.failure(DebugUIError.invalidMimeType))
            return
        }

        let data = Randomness.generateRandomBytes(Int32(dataLength))
        owsAssertDebug(data.count > 0)

        let filePath = OWSFileSystem.temporaryFilePath(fileExtension: fileExtension)
        do {
            try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
            self.filePath = filePath
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }

    // MARK: -

    private static func fakeMissingAssetLoaderWithMimeType(_ mimeType: String) -> DebugUIMessagesAssetLoader? {
        guard let fileExtension = MIMETypeUtil.fileExtension(forMIMEType: mimeType) else {
            owsFailDebug("Invalid mime type: \(mimeType)")
            return nil
        }

        let assetLoader = DebugUIMessagesAssetLoader(filename: "attachment.\(fileExtension)", mimeType: mimeType)
        assetLoader.prepare = { [weak assetLoader] completion in
            assetLoader?.ensureMissingAssetLoaded(completion: completion)
        }
        return assetLoader
    }

    private func ensureMissingAssetLoaded(completion: Completion) {
        guard filePath == nil else {
            completion(.success(()))
            return
        }

        guard let fileExtension = MIMETypeUtil.fileExtension(forMIMEType: mimeType) else {
            completion(.failure(DebugUIError.invalidMimeType))
            return
        }

        let filePath = OWSFileSystem.temporaryFilePath(fileExtension: fileExtension)
        guard FileManager.default.createFile(atPath: filePath, contents: nil) else {
            completion(.failure(DebugUIError.fileCreationFailed))
            return
        }
        self.filePath = filePath
        completion(.success(()))
    }

    // MARK: -

    private static var largeTextSnippet: String {
        let snippet = """
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Suspendisse rutrum, nulla
vitae pretium hendrerit, tellus turpis pharetra libero, vitae sodales tortor ante vel
sem. Fusce sed nisl a lorem gravida tincidunt. Suspendisse efficitur non quam ac
sodales. Aenean ut velit maximus, posuere sem a, accumsan nunc. Donec ullamcorper
turpis lorem. Quisque dignissim purus eu placerat ultricies. Proin at urna eget mi
semper congue. Aenean non elementum ex. Praesent pharetra quam at sem vestibulum,
vestibulum ornare dolor elementum. Vestibulum massa tortor, scelerisque sit amet
pulvinar a, rhoncus vitae nisl. Sed mi nunc, tempus at varius in, malesuada vitae
dui. Vivamus efficitur pulvinar erat vitae congue. Proin vehicula turpis non felis
congue facilisis. Nullam aliquet dapibus ligula ac mollis. Etiam sit amet posuere
lorem, in rhoncus nisi.\n\n
"""
        return (0..<32).reduce(into: "") { result, _ in result += snippet }
    }

    private static func fakeOversizeTextAssetLoader(text: String?) -> DebugUIMessagesAssetLoader {
        let assetLoader = DebugUIMessagesAssetLoader(filename: "attachment.txt", mimeType: OWSMimeTypeOversizeTextMessage)
        assetLoader.prepare = { [weak assetLoader] completion in
            assetLoader?.ensureOversizeTextAssetLoaded(text: text, completion: completion)
        }
        return assetLoader
    }

    private func ensureOversizeTextAssetLoaded(text: String?, completion: Completion) {
        guard filePath == nil else {
            completion(.success(()))
            return
        }

        let largeText = text ?? DebugUIMessagesAssetLoader.largeTextSnippet
        let textData = largeText.data(using: .utf8)!

        let filePath = OWSFileSystem.temporaryFilePath(fileExtension: "txt")
        do {
            try textData.write(to: URL(fileURLWithPath: filePath), options: .atomic)
            self.filePath = filePath
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }
}

#endif
