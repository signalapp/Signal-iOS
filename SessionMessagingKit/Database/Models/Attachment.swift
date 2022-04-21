// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public struct Attachment: Codable, Identifiable, FetchableRecord, PersistableRecord, TableRecord, ColumnExpressible {
    public static var databaseTableName: String { "attachment" }
    internal static let interactionAttachments = belongsTo(InteractionAttachment.self)
    fileprivate static let quote = belongsTo(Quote.self)
    fileprivate static let linkPreview = belongsTo(LinkPreview.self)
    
    public typealias Columns = CodingKeys
    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case serverId
        case variant
        case state
        case contentType
        case byteCount
        case creationTimestamp
        case sourceFilename
        case downloadUrl
        case width
        case height
        case encryptionKey
        case digest
        case caption
    }
    
    public enum Variant: Int, Codable, DatabaseValueConvertible {
        case standard
        case voiceMessage
    }
    
    public enum State: Int, Codable, DatabaseValueConvertible {
        case pending
        case downloading
        case downloaded
        case uploading
        case uploaded
        case failed
    }
    
    /// A unique identifier for the attachment
    public let id: String = UUID().uuidString
    
    /// The id for the attachment returned by the server
    ///
    /// This will be null for attachments which haven’t completed uploading
    ///
    /// **Note:** This value is not unique as multiple SOGS could end up having the same file id
    public let serverId: String?
    
    /// The type of this attachment, used to distinguish logic handling
    public let variant: Variant
    
    /// The current state of the attachment
    public let state: State
    
    /// The MIMEType for the attachment
    public let contentType: String
    
    /// The size of the attachment in bytes
    ///
    /// **Note:** This may be `0` for some legacy attachments
    public let byteCount: UInt
    
    /// Timestamp in seconds since epoch for when this attachment was created
    ///
    /// **Uploaded:** This will be the timestamp the file finished uploading
    /// **Downloaded:** This will be the timestamp the file finished downloading
    /// **Other:** This will be null
    public let creationTimestamp: TimeInterval?
    
    /// Represents the "source" filename sent or received in the protos, not the filename on disk
    public let sourceFilename: String?
    
    /// The url the attachment can be downloaded from, this will be `null` for attachments which haven’t yet been uploaded
    ///
    /// **Note:** The url is a fully constructed url but the clients just extract the id from the end of the url to perform the actual download
    public let downloadUrl: String?
    
    /// The width of the attachment, this will be `null` for non-visual attachment types
    public let width: UInt?
    
    /// The height of the attachment, this will be `null` for non-visual attachment types
    public let height: UInt?
    
    /// The key used to decrypt the attachment
    public let encryptionKey: Data?
    
    /// The computed digest for the attachment (generated from `iv || encrypted data || hmac`)
    public let digest: Data?
    
    /// Caption for the attachment
    public let caption: String?
    
    // MARK: - Initialization
    
    public init(
        serverId: String? = nil,
        variant: Variant,
        state: State = .pending,
        contentType: String,
        byteCount: UInt,
        creationTimestamp: TimeInterval? = nil,
        sourceFilename: String? = nil,
        downloadUrl: String? = nil,
        width: UInt? = nil,
        height: UInt? = nil,
        encryptionKey: Data? = nil,
        digest: Data? = nil,
        caption: String? = nil
    ) {
        self.serverId = serverId
        self.variant = variant
        self.state = state
        self.contentType = contentType
        self.byteCount = byteCount
        self.creationTimestamp = creationTimestamp
        self.sourceFilename = sourceFilename
        self.downloadUrl = downloadUrl
        self.width = width
        self.height = height
        self.encryptionKey = encryptionKey
        self.digest = digest
        self.caption = caption
    }
    
    public init?(
        variant: Variant = .standard,
        contentType: String,
        dataSource: DataSource
    ) {
        guard
            let originalFilePath: String = Attachment.originalFilePath(id: self.id, mimeType: contentType, sourceFilename: nil)
        else {
            return nil
        }
        guard dataSource.write(toPath: originalFilePath) else { return nil }
        
        let imageSize: CGSize? = Attachment.imageSize(
            contentType: contentType,
            originalFilePath: originalFilePath
        )
        
        self.serverId = nil
        self.variant = variant
        self.state = .pending
        self.contentType = contentType
        self.byteCount = dataSource.dataLength()
        self.creationTimestamp = nil
        self.sourceFilename = nil
        self.downloadUrl = nil
        self.width = imageSize.map { UInt(floor($0.width)) }
        self.height = imageSize.map { UInt(floor($0.height)) }
        self.encryptionKey = nil
        self.digest = nil
        self.caption = nil
    }
}

// MARK: - CustomStringConvertible

extension Attachment: CustomStringConvertible {
    public var description: String {
        if MIMETypeUtil.isAudio(contentType) {
            // a missing filename is the legacy way to determine if an audio attachment is
            // a voice note vs. other arbitrary audio attachments.
            if variant == .voiceMessage || self.sourceFilename == nil || (self.sourceFilename?.count ?? 0) == 0 {
                return "🎙️ \("ATTACHMENT_TYPE_VOICE_MESSAGE".localized())"
            }
        }
        
        return "\("ATTACHMENT".localized()) \(emojiForMimeType)"
    }
}

// MARK: - Mutation

public extension Attachment {
    func with(
        serverId: String? = nil,
        state: State? = nil,
        downloadUrl: String? = nil,
        encryptionKey: Data? = nil,
        digest: Data? = nil
    ) -> Attachment {
        return Attachment(
            serverId: (serverId ?? self.serverId),
            variant: variant,
            state: (state ?? self.state),
            contentType: contentType,
            byteCount: byteCount,
            creationTimestamp: creationTimestamp,
            sourceFilename: sourceFilename,
            downloadUrl: (downloadUrl ?? self.downloadUrl),
            width: width,
            height: height,
            encryptionKey: (encryptionKey ?? self.encryptionKey),
            digest: (digest ?? self.digest),
            caption: self.caption
        )
    }
}

// MARK: - Protobuf

public extension Attachment {
    init(proto: SNProtoAttachmentPointer) {
        func inferContentType(from filename: String?) -> String {
            guard
                let fileName: String = filename,
                let fileExtension: String = URL(string: fileName)?.pathExtension
            else { return OWSMimeTypeApplicationOctetStream }
            
            return (MIMETypeUtil.mimeType(forFileExtension: fileExtension) ?? OWSMimeTypeApplicationOctetStream)
        }
        
        self.serverId = nil
        self.variant = {
            let voiceMessageFlag: Int32 = SNProtoAttachmentPointer.SNProtoAttachmentPointerFlags
                .voiceMessage
                .rawValue
            
            guard proto.hasFlags && ((proto.flags & UInt32(voiceMessageFlag)) > 0) else {
                return .standard
            }
            
            return .voiceMessage
        }()
        self.state = .pending
        self.contentType = (proto.contentType ?? inferContentType(from: proto.fileName))
        self.byteCount = UInt(proto.size)
        self.creationTimestamp = nil
        self.sourceFilename = proto.fileName
        self.downloadUrl = proto.url
        self.width = (proto.hasWidth && proto.width > 0 ? UInt(proto.width) : nil)
        self.height = (proto.hasHeight && proto.height > 0 ? UInt(proto.height) : nil)
        self.encryptionKey = proto.key
        self.digest = proto.digest
        self.caption = (proto.hasCaption ? proto.caption : nil)
    }
    
    func buildProto() -> SNProtoAttachmentPointer? {
        guard let serverId: UInt64 = UInt64(self.serverId ?? "") else { return nil }
        
        let builder = SNProtoAttachmentPointer.builder(id: serverId)
        builder.setContentType(contentType)
        
        if let sourceFilename: String = sourceFilename, !sourceFilename.isEmpty {
            builder.setFileName(sourceFilename)
        }
        
        if let caption: String = self.caption, !caption.isEmpty {
            builder.setCaption(caption)
        }
        
        builder.setSize(UInt32(byteCount))
        builder.setFlags(variant == .voiceMessage ?
            UInt32(SNProtoAttachmentPointer.SNProtoAttachmentPointerFlags.voiceMessage.rawValue) :
            0
        )
        
        if let encryptionKey: Data = encryptionKey, let digest: Data = digest {
            builder.setKey(encryptionKey)
            builder.setDigest(digest)
        }
        
        if
            let width: UInt = self.width,
            let height: UInt = self.height,
            width > 0,
            width < Int.max,
            height > 0,
            height < Int.max
        {
            builder.setWidth(UInt32(width))
            builder.setHeight(UInt32(height))
        }
        
        if let downloadUrl: String = self.downloadUrl {
            builder.setUrl(downloadUrl)
        }
        
        do {
            return try builder.build()
        }
        catch {
            SNLog("Couldn't construct attachment proto from: \(self).")
            return nil
        }
    }
}

// MARK: - GRDB Interactions

public extension Attachment {
    static func fetchAllPendingAttachments(_ db: Database, for threadId: String) throws -> [Attachment] {
        return try Attachment
            .select(Attachment.Columns.allCases + [Interaction.Columns.id])
            .filter(Columns.variant == Variant.standard)
            .filter(Columns.state == State.pending)
            .joining(
                optional: Attachment.interactionAttachments
                    .filter(Interaction.Columns.threadId == threadId)
            )
            .joining(
                optional: Attachment.quote
                    .joining(
                        required: Quote.interaction
                            .filter(Interaction.Columns.threadId == threadId)
                    )
            )//tmp.authorId
            .joining(
                optional: Attachment.linkPreview
                    .joining(
                        required: LinkPreview.interactions
                            .filter(Interaction.Columns.threadId == threadId)
                    )
            )
            .order(Interaction.Columns.id.desc) // Newest attachments first
            .fetchAll(db)
    }
}

// MARK: - Convenience - Static

public extension Attachment {
    private static let thumbnailDimensionSmall: UInt = 200
    private static let thumbnailDimensionMedium: UInt = 450
    
    /// This size is large enough to render full screen
    private static var thumbnailDimensionsLarge: CGFloat = {
        let screenSizePoints: CGSize = UIScreen.main.bounds.size
        let minZoomFactor: CGFloat = 2  // TODO: Should this be screen scale?
        
        return (max(screenSizePoints.width, screenSizePoints.height) * minZoomFactor)
    }()
    
    private static var sharedDataAttachmentsDirPath: String = {
        OWSFileSystem.appSharedDataDirectoryPath().appending("/Attachments")
    }()
    
    private static var attachmentsFolder: String = {
        let attachmentsFolder: String = sharedDataAttachmentsDirPath
        OWSFileSystem.ensureDirectoryExists(attachmentsFolder)
        
        return attachmentsFolder
    }()
    
    private static var thumbnailsFolder: String = {
        let attachmentsFolder: String = sharedDataAttachmentsDirPath
        OWSFileSystem.ensureDirectoryExists(attachmentsFolder)
        
        return attachmentsFolder
    }()
    
    private static func originalFilePath(id: String, mimeType: String, sourceFilename: String?) -> String? {
        let maybeFilePath: String? = MIMETypeUtil.filePath(
            forAttachment: id, // TODO: Can we avoid this???
            ofMIMEType: mimeType,
            sourceFilename: sourceFilename,
            inFolder: Attachment.attachmentsFolder
        )
        
        guard let filePath: String = maybeFilePath else { return nil }
        guard filePath.hasPrefix(Attachment.attachmentsFolder) else { return nil }
        
        let localRelativeFilePath: String = filePath.substring(from: Attachment.attachmentsFolder.count)
        
        guard !localRelativeFilePath.isEmpty else { return nil }

        return localRelativeFilePath
    }
    
    static func imageSize(contentType: String, originalFilePath: String) -> CGSize? {
        let isVideo: Bool = MIMETypeUtil.isVideo(contentType)
        let isImage: Bool = MIMETypeUtil.isImage(contentType)
        let isAnimated: Bool = MIMETypeUtil.isAnimated(contentType)
        
        guard isVideo || isImage || isAnimated else { return nil }
        
        if isVideo {
            guard OWSMediaUtils.isValidVideo(path: originalFilePath) else { return nil }
            
            return Attachment.videoStillImage(filePath: originalFilePath)?.size
        }
        
        return NSData.imageSize(forFilePath: originalFilePath, mimeType: contentType)
    }
    
    static func videoStillImage(filePath: String) -> UIImage? {
        return try? OWSMediaUtils.thumbnail(
            forVideoAtPath: filePath,
            maxDimension: Attachment.thumbnailDimensionsLarge
        )
    }
}

// MARK: - Convenience

extension Attachment {
    var originalFilePath: String? {
        return Attachment.originalFilePath(
            id: self.id,
            mimeType: self.contentType,
            sourceFilename: self.sourceFilename
        )
    }
    
    var localRelativeFilePath: String? {
        return originalFilePath?.substring(from: Attachment.attachmentsFolder.count)
    }
    
    var thumbnailsDirPath: String {
        // Thumbnails are written to the caches directory, so that iOS can
        // remove them if necessary
        return "\(OWSFileSystem.cachesDirectoryPath())/\(id)-thumbnails"
    }
    
    var originalImage: UIImage? {
        guard let originalFilePath: String = originalFilePath else { return nil }
        
        if isVideo {
            return Attachment.videoStillImage(filePath: originalFilePath)
        }
        
        guard isImage || isAnimated else { return nil }
        guard NSData.ows_isValidImage(atPath: originalFilePath, mimeType: contentType) else {
            return nil
        }
        
        return UIImage(contentsOfFile: originalFilePath)
    }
    
    var emojiForMimeType: String {
        if MIMETypeUtil.isImage(contentType) {
            return "📷"
        }
        else if MIMETypeUtil.isVideo(contentType) {
            return "🎥"
        }
        else if MIMETypeUtil.isAudio(contentType) {
            return "🎧"
        }
        else if MIMETypeUtil.isAnimated(contentType) {
            return "🎡"
        }
        
        return "📎"
    }
    
    var isImage: Bool { MIMETypeUtil.isImage(contentType) }
    var isVideo: Bool { MIMETypeUtil.isVideo(contentType) }
    var isAnimated: Bool { MIMETypeUtil.isAnimated(contentType) }
    
    func readDataFromFile() throws -> Data? {
        guard let filePath: String = Attachment.originalFilePath(id: self.id, mimeType: self.contentType, sourceFilename: self.sourceFilename) else {
            return nil
        }
        
        return try Data(contentsOf: URL(fileURLWithPath: filePath))
    }
    
    public func thumbnailPath(for dimensions: UInt) -> String {
        return "\(thumbnailsDirPath)/thumbnail-\(dimensions).jpg"
    }
    
    private func loadThumbnail(with dimensions: UInt, success: @escaping (UIImage) -> (), failure: @escaping () -> ()) {
        guard let width: UInt = self.width, let height: UInt = self.height, width > 1, height > 1 else {
            failure()
            return
        }
        
        // There's no point in generating a thumbnail if the original is smaller than the
        // thumbnail size
        if width < dimensions || height < dimensions {
            guard let image: UIImage = originalImage else {
                failure()
                return
            }
            
            success(image)
            return
        }
        
        let thumbnailPath = thumbnailPath(for: dimensions)
        
        if FileManager.default.fileExists(atPath: thumbnailPath) {
            guard let image: UIImage = UIImage(contentsOfFile: thumbnailPath) else {
                failure()
                return
            }
            
            success(image)
            return
        }
        
        OWSThumbnailService.shared.ensureThumbnail(
            for: self,
            dimensions: dimensions,
            success: { loadedThumbnail in success(loadedThumbnail.image) },
            failure: { _ in failure() }
        )
    }
    
    func thumbnailImageSmallSync() -> UIImage? {
        guard isVideo || isImage || isAnimated else { return nil }
        
        let semaphore: DispatchSemaphore = DispatchSemaphore(value: 0)
        var image: UIImage?
        
        loadThumbnail(
            with: Attachment.thumbnailDimensionSmall,
            success: { loadedImage in
                image = loadedImage
                semaphore.signal()
            },
            failure: { semaphore.signal() }
        )

        // Wait up to 5 seconds for the thumbnail to be loaded
        _ = semaphore.wait(timeout: .now() + .seconds(5))
        
        return image
    }
    
    public func cloneAsThumbnail() -> Attachment {
        fatalError("TODO: Add this back")
    }
}
