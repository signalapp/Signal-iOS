//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

// WARNING: This code is generated. Only edit within the markers.

public enum SignalIOSProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - SignalIOSProtoBackupSnapshotBackupEntity

@objc public class SignalIOSProtoBackupSnapshotBackupEntity: NSObject {

	// MARK: - SignalIOSProtoBackupSnapshotBackupEntityType

	@objc public enum SignalIOSProtoBackupSnapshotBackupEntityType: Int32 {
		case unknown = 0
		case migration = 1
		case thread = 2
		case interaction = 3
		case attachment = 4
	}

	private class func SignalIOSProtoBackupSnapshotBackupEntityTypeWrap(_ value: IOSProtos_BackupSnapshot.BackupEntity.TypeEnum) -> SignalIOSProtoBackupSnapshotBackupEntityType {
		switch value {
		case .unknown: return .unknown
		case .migration: return .migration
		case .thread: return .thread
		case .interaction: return .interaction
		case .attachment: return .attachment
		}
	}

	private class func SignalIOSProtoBackupSnapshotBackupEntityTypeUnwrap(_ value: SignalIOSProtoBackupSnapshotBackupEntityType) -> IOSProtos_BackupSnapshot.BackupEntity.TypeEnum {
		switch value {
		case .unknown: return .unknown
		case .migration: return .migration
		case .thread: return .thread
		case .interaction: return .interaction
		case .attachment: return .attachment
		}
	}

	@objc public let type: SignalIOSProtoBackupSnapshotBackupEntityType
	@objc public let entityData: Data?

	@objc public init(type: SignalIOSProtoBackupSnapshotBackupEntityType,
	                  entityData: Data?) {
		self.type = type
		self.entityData = entityData
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SignalIOSProtoBackupSnapshotBackupEntity {
		let proto = try IOSProtos_BackupSnapshot.BackupEntity(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: IOSProtos_BackupSnapshot.BackupEntity) throws -> SignalIOSProtoBackupSnapshotBackupEntity {
		var type: SignalIOSProtoBackupSnapshotBackupEntityType = .unknown
		if proto.hasType {
			type = SignalIOSProtoBackupSnapshotBackupEntityTypeWrap(proto.type)
		}

		var entityData: Data? = nil
		if proto.hasEntityData {
			entityData = proto.entityData
		}

		// MARK: - Begin Validation Logic for SignalIOSProtoBackupSnapshotBackupEntity -

		// MARK: - End Validation Logic for SignalIOSProtoBackupSnapshotBackupEntity -

		let result = SignalIOSProtoBackupSnapshotBackupEntity(type: type,
		                                                      entityData: entityData)
		return result
	}

	fileprivate var asProtobuf: IOSProtos_BackupSnapshot.BackupEntity {
		let proto = IOSProtos_BackupSnapshot.BackupEntity.with { (builder) in
			builder.type = SignalIOSProtoBackupSnapshotBackupEntity.SignalIOSProtoBackupSnapshotBackupEntityTypeUnwrap(self.type)

			if let entityData = self.entityData {
				builder.entityData = entityData
			}
		}

		return proto
	}
}

// MARK: - SignalIOSProtoBackupSnapshot

@objc public class SignalIOSProtoBackupSnapshot: NSObject {

	@objc public let entity: [SignalIOSProtoBackupSnapshotBackupEntity]

	@objc public init(entity: [SignalIOSProtoBackupSnapshotBackupEntity]) {
		self.entity = entity
	}

	@objc
	public func serializedData() throws -> Data {
	    return try self.asProtobuf.serializedData()
	}

	@objc public class func parseData(_ serializedData: Data) throws -> SignalIOSProtoBackupSnapshot {
		let proto = try IOSProtos_BackupSnapshot(serializedData: serializedData)
		return try parseProto(proto)
	}

	fileprivate class func parseProto(_ proto: IOSProtos_BackupSnapshot) throws -> SignalIOSProtoBackupSnapshot {
		var entity: [SignalIOSProtoBackupSnapshotBackupEntity] = []
		for item in proto.entity {
			let wrapped = try SignalIOSProtoBackupSnapshotBackupEntity.parseProto(item)
			entity.append(wrapped)
		}

		// MARK: - Begin Validation Logic for SignalIOSProtoBackupSnapshot -

		// MARK: - End Validation Logic for SignalIOSProtoBackupSnapshot -

		let result = SignalIOSProtoBackupSnapshot(entity: entity)
		return result
	}

	fileprivate var asProtobuf: IOSProtos_BackupSnapshot {
		let proto = IOSProtos_BackupSnapshot.with { (builder) in
			var entityUnwrapped = [IOSProtos_BackupSnapshot.BackupEntity]()
			for item in entity {
				entityUnwrapped.append(item.asProtobuf)
			}
			builder.entity = entityUnwrapped
		}

		return proto
	}
}
