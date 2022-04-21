// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import GRDB
import SessionUtilitiesKit

public final class DataExtractionNotification : ControlMessage {
    private enum CodingKeys: String, CodingKey {
        case kind
    }
    
    public var kind: Kind?
    
    // MARK: Kind
    public enum Kind: CustomStringConvertible, Codable {
        case screenshot
        case mediaSaved(timestamp: UInt64)

        public var description: String {
            switch self {
            case .screenshot: return "screenshot"
            case .mediaSaved: return "mediaSaved"
            }
        }
    }

    // MARK: Initialization
    public override init() { super.init() }

    internal init(kind: Kind) {
        super.init()
        self.kind = kind
    }

    // MARK: Validation
    public override var isValid: Bool {
        guard super.isValid, let kind = kind else { return false }
        switch kind {
        case .screenshot: return true
        case .mediaSaved(let timestamp): return timestamp > 0
        }
    }

    // MARK: Coding
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        guard let rawKind = coder.decodeObject(forKey: "kind") as? String else { return nil }
        switch rawKind {
        case "screenshot":
            self.kind = .screenshot
        case "mediaSaved":
            guard let timestamp = coder.decodeObject(forKey: "timestamp") as? UInt64 else { return nil }
            self.kind = .mediaSaved(timestamp: timestamp)
        default: return nil
        }
    }

    public override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        guard let kind = kind else { return }
        switch kind {
        case .screenshot:
            coder.encode("screenshot", forKey: "kind")
        case .mediaSaved(let timestamp):
            coder.encode("mediaSaved", forKey: "kind")
            coder.encode(timestamp, forKey: "timestamp")
        }
    }
    
    // MARK: - Codable
    
    required init(from decoder: Decoder) throws {
        try super.init(from: decoder)
        
        let container: KeyedDecodingContainer<CodingKeys> = try decoder.container(keyedBy: CodingKeys.self)
        
        kind = try? container.decode(Kind.self, forKey: .kind)
    }
    
    public override func encode(to encoder: Encoder) throws {
        try super.encode(to: encoder)
        
        var container: KeyedEncodingContainer<CodingKeys> = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encodeIfPresent(kind, forKey: .kind)
    }

    // MARK: Proto Conversion
    public override class func fromProto(_ proto: SNProtoContent, sender: String) -> DataExtractionNotification? {
        guard let dataExtractionNotification = proto.dataExtractionNotification else { return nil }
        let kind: Kind
        switch dataExtractionNotification.type {
        case .screenshot: kind = .screenshot
        case .mediaSaved:
            let timestamp = dataExtractionNotification.hasTimestamp ? dataExtractionNotification.timestamp : 0
            kind = .mediaSaved(timestamp: timestamp)
        }
        return DataExtractionNotification(kind: kind)
    }

    public override func toProto(_ db: Database) -> SNProtoContent? {
        guard let kind = kind else {
            SNLog("Couldn't construct data extraction notification proto from: \(self).")
            return nil
        }
        do {
            let dataExtractionNotification: SNProtoDataExtractionNotification.SNProtoDataExtractionNotificationBuilder
            switch kind {
            case .screenshot:
                dataExtractionNotification = SNProtoDataExtractionNotification.builder(type: .screenshot)
            case .mediaSaved(let timestamp):
                dataExtractionNotification = SNProtoDataExtractionNotification.builder(type: .mediaSaved)
                dataExtractionNotification.setTimestamp(timestamp)
            }
            let contentProto = SNProtoContent.builder()
            contentProto.setDataExtractionNotification(try dataExtractionNotification.build())
            return try contentProto.build()
        } catch {
            SNLog("Couldn't construct data extraction notification proto from: \(self).")
            return nil
        }
    }

    // MARK: Description
    public override var description: String {
        """
        DataExtractionNotification(
            kind: \(kind?.description ?? "null")
        )
        """
    }
}
