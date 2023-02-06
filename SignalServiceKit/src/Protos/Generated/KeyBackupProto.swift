//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SwiftProtobuf

// WARNING: This code is generated. Only edit within the markers.

public enum KeyBackupProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - KeyBackupProtoRequest

@objc
public class KeyBackupProtoRequest: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: KeyBackupProtos_Request

    @objc
    public let backup: KeyBackupProtoBackupRequest?

    @objc
    public let restore: KeyBackupProtoRestoreRequest?

    @objc
    public let delete: KeyBackupProtoDeleteRequest?

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: KeyBackupProtos_Request,
                 backup: KeyBackupProtoBackupRequest?,
                 restore: KeyBackupProtoRestoreRequest?,
                 delete: KeyBackupProtoDeleteRequest?) {
        self.proto = proto
        self.backup = backup
        self.restore = restore
        self.delete = delete
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try KeyBackupProtos_Request(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: KeyBackupProtos_Request) {
        var backup: KeyBackupProtoBackupRequest?
        if proto.hasBackup {
            backup = KeyBackupProtoBackupRequest(proto.backup)
        }

        var restore: KeyBackupProtoRestoreRequest?
        if proto.hasRestore {
            restore = KeyBackupProtoRestoreRequest(proto.restore)
        }

        var delete: KeyBackupProtoDeleteRequest?
        if proto.hasDelete {
            delete = KeyBackupProtoDeleteRequest(proto.delete)
        }

        self.init(proto: proto,
                  backup: backup,
                  restore: restore,
                  delete: delete)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension KeyBackupProtoRequest {
    @objc
    public static func builder() -> KeyBackupProtoRequestBuilder {
        return KeyBackupProtoRequestBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> KeyBackupProtoRequestBuilder {
        let builder = KeyBackupProtoRequestBuilder()
        if let _value = backup {
            builder.setBackup(_value)
        }
        if let _value = restore {
            builder.setRestore(_value)
        }
        if let _value = delete {
            builder.setDelete(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class KeyBackupProtoRequestBuilder: NSObject {

    private var proto = KeyBackupProtos_Request()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setBackup(_ valueParam: KeyBackupProtoBackupRequest?) {
        guard let valueParam = valueParam else { return }
        proto.backup = valueParam.proto
    }

    public func setBackup(_ valueParam: KeyBackupProtoBackupRequest) {
        proto.backup = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setRestore(_ valueParam: KeyBackupProtoRestoreRequest?) {
        guard let valueParam = valueParam else { return }
        proto.restore = valueParam.proto
    }

    public func setRestore(_ valueParam: KeyBackupProtoRestoreRequest) {
        proto.restore = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDelete(_ valueParam: KeyBackupProtoDeleteRequest?) {
        guard let valueParam = valueParam else { return }
        proto.delete = valueParam.proto
    }

    public func setDelete(_ valueParam: KeyBackupProtoDeleteRequest) {
        proto.delete = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> KeyBackupProtoRequest {
        return KeyBackupProtoRequest(proto)
    }

    @objc
    public func buildInfallibly() -> KeyBackupProtoRequest {
        return KeyBackupProtoRequest(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try KeyBackupProtoRequest(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension KeyBackupProtoRequest {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoRequestBuilder {
    @objc
    public func buildIgnoringErrors() -> KeyBackupProtoRequest? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - KeyBackupProtoResponse

@objc
public class KeyBackupProtoResponse: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: KeyBackupProtos_Response

    @objc
    public let backup: KeyBackupProtoBackupResponse?

    @objc
    public let restore: KeyBackupProtoRestoreResponse?

    @objc
    public let delete: KeyBackupProtoDeleteResponse?

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: KeyBackupProtos_Response,
                 backup: KeyBackupProtoBackupResponse?,
                 restore: KeyBackupProtoRestoreResponse?,
                 delete: KeyBackupProtoDeleteResponse?) {
        self.proto = proto
        self.backup = backup
        self.restore = restore
        self.delete = delete
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try KeyBackupProtos_Response(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: KeyBackupProtos_Response) {
        var backup: KeyBackupProtoBackupResponse?
        if proto.hasBackup {
            backup = KeyBackupProtoBackupResponse(proto.backup)
        }

        var restore: KeyBackupProtoRestoreResponse?
        if proto.hasRestore {
            restore = KeyBackupProtoRestoreResponse(proto.restore)
        }

        var delete: KeyBackupProtoDeleteResponse?
        if proto.hasDelete {
            delete = KeyBackupProtoDeleteResponse(proto.delete)
        }

        self.init(proto: proto,
                  backup: backup,
                  restore: restore,
                  delete: delete)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension KeyBackupProtoResponse {
    @objc
    public static func builder() -> KeyBackupProtoResponseBuilder {
        return KeyBackupProtoResponseBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> KeyBackupProtoResponseBuilder {
        let builder = KeyBackupProtoResponseBuilder()
        if let _value = backup {
            builder.setBackup(_value)
        }
        if let _value = restore {
            builder.setRestore(_value)
        }
        if let _value = delete {
            builder.setDelete(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class KeyBackupProtoResponseBuilder: NSObject {

    private var proto = KeyBackupProtos_Response()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setBackup(_ valueParam: KeyBackupProtoBackupResponse?) {
        guard let valueParam = valueParam else { return }
        proto.backup = valueParam.proto
    }

    public func setBackup(_ valueParam: KeyBackupProtoBackupResponse) {
        proto.backup = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setRestore(_ valueParam: KeyBackupProtoRestoreResponse?) {
        guard let valueParam = valueParam else { return }
        proto.restore = valueParam.proto
    }

    public func setRestore(_ valueParam: KeyBackupProtoRestoreResponse) {
        proto.restore = valueParam.proto
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setDelete(_ valueParam: KeyBackupProtoDeleteResponse?) {
        guard let valueParam = valueParam else { return }
        proto.delete = valueParam.proto
    }

    public func setDelete(_ valueParam: KeyBackupProtoDeleteResponse) {
        proto.delete = valueParam.proto
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> KeyBackupProtoResponse {
        return KeyBackupProtoResponse(proto)
    }

    @objc
    public func buildInfallibly() -> KeyBackupProtoResponse {
        return KeyBackupProtoResponse(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try KeyBackupProtoResponse(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension KeyBackupProtoResponse {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoResponseBuilder {
    @objc
    public func buildIgnoringErrors() -> KeyBackupProtoResponse? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - KeyBackupProtoBackupRequest

@objc
public class KeyBackupProtoBackupRequest: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: KeyBackupProtos_BackupRequest

    @objc
    public var serviceID: Data? {
        guard hasServiceID else {
            return nil
        }
        return proto.serviceID
    }
    @objc
    public var hasServiceID: Bool {
        return proto.hasServiceID
    }

    @objc
    public var backupID: Data? {
        guard hasBackupID else {
            return nil
        }
        return proto.backupID
    }
    @objc
    public var hasBackupID: Bool {
        return proto.hasBackupID
    }

    @objc
    public var token: Data? {
        guard hasToken else {
            return nil
        }
        return proto.token
    }
    @objc
    public var hasToken: Bool {
        return proto.hasToken
    }

    @objc
    public var validFrom: UInt64 {
        return proto.validFrom
    }
    @objc
    public var hasValidFrom: Bool {
        return proto.hasValidFrom
    }

    @objc
    public var data: Data? {
        guard hasData else {
            return nil
        }
        return proto.data
    }
    @objc
    public var hasData: Bool {
        return proto.hasData
    }

    @objc
    public var pin: Data? {
        guard hasPin else {
            return nil
        }
        return proto.pin
    }
    @objc
    public var hasPin: Bool {
        return proto.hasPin
    }

    @objc
    public var tries: UInt32 {
        return proto.tries
    }
    @objc
    public var hasTries: Bool {
        return proto.hasTries
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: KeyBackupProtos_BackupRequest) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try KeyBackupProtos_BackupRequest(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: KeyBackupProtos_BackupRequest) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension KeyBackupProtoBackupRequest {
    @objc
    public static func builder() -> KeyBackupProtoBackupRequestBuilder {
        return KeyBackupProtoBackupRequestBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> KeyBackupProtoBackupRequestBuilder {
        let builder = KeyBackupProtoBackupRequestBuilder()
        if let _value = serviceID {
            builder.setServiceID(_value)
        }
        if let _value = backupID {
            builder.setBackupID(_value)
        }
        if let _value = token {
            builder.setToken(_value)
        }
        if hasValidFrom {
            builder.setValidFrom(validFrom)
        }
        if let _value = data {
            builder.setData(_value)
        }
        if let _value = pin {
            builder.setPin(_value)
        }
        if hasTries {
            builder.setTries(tries)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class KeyBackupProtoBackupRequestBuilder: NSObject {

    private var proto = KeyBackupProtos_BackupRequest()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setServiceID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.serviceID = valueParam
    }

    public func setServiceID(_ valueParam: Data) {
        proto.serviceID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setBackupID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.backupID = valueParam
    }

    public func setBackupID(_ valueParam: Data) {
        proto.backupID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setToken(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.token = valueParam
    }

    public func setToken(_ valueParam: Data) {
        proto.token = valueParam
    }

    @objc
    public func setValidFrom(_ valueParam: UInt64) {
        proto.validFrom = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setData(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.data = valueParam
    }

    public func setData(_ valueParam: Data) {
        proto.data = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPin(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.pin = valueParam
    }

    public func setPin(_ valueParam: Data) {
        proto.pin = valueParam
    }

    @objc
    public func setTries(_ valueParam: UInt32) {
        proto.tries = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> KeyBackupProtoBackupRequest {
        return KeyBackupProtoBackupRequest(proto)
    }

    @objc
    public func buildInfallibly() -> KeyBackupProtoBackupRequest {
        return KeyBackupProtoBackupRequest(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try KeyBackupProtoBackupRequest(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension KeyBackupProtoBackupRequest {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoBackupRequestBuilder {
    @objc
    public func buildIgnoringErrors() -> KeyBackupProtoBackupRequest? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - KeyBackupProtoBackupResponseStatus

@objc
public enum KeyBackupProtoBackupResponseStatus: Int32 {
    case ok = 1
    case alreadyExists = 2
    case notYetValid = 3
}

private func KeyBackupProtoBackupResponseStatusWrap(_ value: KeyBackupProtos_BackupResponse.Status) -> KeyBackupProtoBackupResponseStatus {
    switch value {
    case .ok: return .ok
    case .alreadyExists: return .alreadyExists
    case .notYetValid: return .notYetValid
    }
}

private func KeyBackupProtoBackupResponseStatusUnwrap(_ value: KeyBackupProtoBackupResponseStatus) -> KeyBackupProtos_BackupResponse.Status {
    switch value {
    case .ok: return .ok
    case .alreadyExists: return .alreadyExists
    case .notYetValid: return .notYetValid
    }
}

// MARK: - KeyBackupProtoBackupResponse

@objc
public class KeyBackupProtoBackupResponse: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: KeyBackupProtos_BackupResponse

    public var status: KeyBackupProtoBackupResponseStatus? {
        guard hasStatus else {
            return nil
        }
        return KeyBackupProtoBackupResponseStatusWrap(proto.status)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedStatus: KeyBackupProtoBackupResponseStatus {
        if !hasStatus {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: BackupResponse.status.")
        }
        return KeyBackupProtoBackupResponseStatusWrap(proto.status)
    }
    @objc
    public var hasStatus: Bool {
        return proto.hasStatus
    }

    @objc
    public var token: Data? {
        guard hasToken else {
            return nil
        }
        return proto.token
    }
    @objc
    public var hasToken: Bool {
        return proto.hasToken
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: KeyBackupProtos_BackupResponse) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try KeyBackupProtos_BackupResponse(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: KeyBackupProtos_BackupResponse) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension KeyBackupProtoBackupResponse {
    @objc
    public static func builder() -> KeyBackupProtoBackupResponseBuilder {
        return KeyBackupProtoBackupResponseBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> KeyBackupProtoBackupResponseBuilder {
        let builder = KeyBackupProtoBackupResponseBuilder()
        if let _value = status {
            builder.setStatus(_value)
        }
        if let _value = token {
            builder.setToken(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class KeyBackupProtoBackupResponseBuilder: NSObject {

    private var proto = KeyBackupProtos_BackupResponse()

    @objc
    fileprivate override init() {}

    @objc
    public func setStatus(_ valueParam: KeyBackupProtoBackupResponseStatus) {
        proto.status = KeyBackupProtoBackupResponseStatusUnwrap(valueParam)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setToken(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.token = valueParam
    }

    public func setToken(_ valueParam: Data) {
        proto.token = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> KeyBackupProtoBackupResponse {
        return KeyBackupProtoBackupResponse(proto)
    }

    @objc
    public func buildInfallibly() -> KeyBackupProtoBackupResponse {
        return KeyBackupProtoBackupResponse(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try KeyBackupProtoBackupResponse(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension KeyBackupProtoBackupResponse {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoBackupResponseBuilder {
    @objc
    public func buildIgnoringErrors() -> KeyBackupProtoBackupResponse? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - KeyBackupProtoRestoreRequest

@objc
public class KeyBackupProtoRestoreRequest: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: KeyBackupProtos_RestoreRequest

    @objc
    public var serviceID: Data? {
        guard hasServiceID else {
            return nil
        }
        return proto.serviceID
    }
    @objc
    public var hasServiceID: Bool {
        return proto.hasServiceID
    }

    @objc
    public var backupID: Data? {
        guard hasBackupID else {
            return nil
        }
        return proto.backupID
    }
    @objc
    public var hasBackupID: Bool {
        return proto.hasBackupID
    }

    @objc
    public var token: Data? {
        guard hasToken else {
            return nil
        }
        return proto.token
    }
    @objc
    public var hasToken: Bool {
        return proto.hasToken
    }

    @objc
    public var validFrom: UInt64 {
        return proto.validFrom
    }
    @objc
    public var hasValidFrom: Bool {
        return proto.hasValidFrom
    }

    @objc
    public var pin: Data? {
        guard hasPin else {
            return nil
        }
        return proto.pin
    }
    @objc
    public var hasPin: Bool {
        return proto.hasPin
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: KeyBackupProtos_RestoreRequest) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try KeyBackupProtos_RestoreRequest(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: KeyBackupProtos_RestoreRequest) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension KeyBackupProtoRestoreRequest {
    @objc
    public static func builder() -> KeyBackupProtoRestoreRequestBuilder {
        return KeyBackupProtoRestoreRequestBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> KeyBackupProtoRestoreRequestBuilder {
        let builder = KeyBackupProtoRestoreRequestBuilder()
        if let _value = serviceID {
            builder.setServiceID(_value)
        }
        if let _value = backupID {
            builder.setBackupID(_value)
        }
        if let _value = token {
            builder.setToken(_value)
        }
        if hasValidFrom {
            builder.setValidFrom(validFrom)
        }
        if let _value = pin {
            builder.setPin(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class KeyBackupProtoRestoreRequestBuilder: NSObject {

    private var proto = KeyBackupProtos_RestoreRequest()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setServiceID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.serviceID = valueParam
    }

    public func setServiceID(_ valueParam: Data) {
        proto.serviceID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setBackupID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.backupID = valueParam
    }

    public func setBackupID(_ valueParam: Data) {
        proto.backupID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setToken(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.token = valueParam
    }

    public func setToken(_ valueParam: Data) {
        proto.token = valueParam
    }

    @objc
    public func setValidFrom(_ valueParam: UInt64) {
        proto.validFrom = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setPin(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.pin = valueParam
    }

    public func setPin(_ valueParam: Data) {
        proto.pin = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> KeyBackupProtoRestoreRequest {
        return KeyBackupProtoRestoreRequest(proto)
    }

    @objc
    public func buildInfallibly() -> KeyBackupProtoRestoreRequest {
        return KeyBackupProtoRestoreRequest(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try KeyBackupProtoRestoreRequest(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension KeyBackupProtoRestoreRequest {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoRestoreRequestBuilder {
    @objc
    public func buildIgnoringErrors() -> KeyBackupProtoRestoreRequest? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - KeyBackupProtoRestoreResponseStatus

@objc
public enum KeyBackupProtoRestoreResponseStatus: Int32 {
    case ok = 1
    case tokenMismatch = 2
    case notYetValid = 3
    case missing = 4
    case pinMismatch = 5
}

private func KeyBackupProtoRestoreResponseStatusWrap(_ value: KeyBackupProtos_RestoreResponse.Status) -> KeyBackupProtoRestoreResponseStatus {
    switch value {
    case .ok: return .ok
    case .tokenMismatch: return .tokenMismatch
    case .notYetValid: return .notYetValid
    case .missing: return .missing
    case .pinMismatch: return .pinMismatch
    }
}

private func KeyBackupProtoRestoreResponseStatusUnwrap(_ value: KeyBackupProtoRestoreResponseStatus) -> KeyBackupProtos_RestoreResponse.Status {
    switch value {
    case .ok: return .ok
    case .tokenMismatch: return .tokenMismatch
    case .notYetValid: return .notYetValid
    case .missing: return .missing
    case .pinMismatch: return .pinMismatch
    }
}

// MARK: - KeyBackupProtoRestoreResponse

@objc
public class KeyBackupProtoRestoreResponse: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: KeyBackupProtos_RestoreResponse

    public var status: KeyBackupProtoRestoreResponseStatus? {
        guard hasStatus else {
            return nil
        }
        return KeyBackupProtoRestoreResponseStatusWrap(proto.status)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc
    public var unwrappedStatus: KeyBackupProtoRestoreResponseStatus {
        if !hasStatus {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: RestoreResponse.status.")
        }
        return KeyBackupProtoRestoreResponseStatusWrap(proto.status)
    }
    @objc
    public var hasStatus: Bool {
        return proto.hasStatus
    }

    @objc
    public var token: Data? {
        guard hasToken else {
            return nil
        }
        return proto.token
    }
    @objc
    public var hasToken: Bool {
        return proto.hasToken
    }

    @objc
    public var data: Data? {
        guard hasData else {
            return nil
        }
        return proto.data
    }
    @objc
    public var hasData: Bool {
        return proto.hasData
    }

    @objc
    public var tries: UInt32 {
        return proto.tries
    }
    @objc
    public var hasTries: Bool {
        return proto.hasTries
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: KeyBackupProtos_RestoreResponse) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try KeyBackupProtos_RestoreResponse(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: KeyBackupProtos_RestoreResponse) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension KeyBackupProtoRestoreResponse {
    @objc
    public static func builder() -> KeyBackupProtoRestoreResponseBuilder {
        return KeyBackupProtoRestoreResponseBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> KeyBackupProtoRestoreResponseBuilder {
        let builder = KeyBackupProtoRestoreResponseBuilder()
        if let _value = status {
            builder.setStatus(_value)
        }
        if let _value = token {
            builder.setToken(_value)
        }
        if let _value = data {
            builder.setData(_value)
        }
        if hasTries {
            builder.setTries(tries)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class KeyBackupProtoRestoreResponseBuilder: NSObject {

    private var proto = KeyBackupProtos_RestoreResponse()

    @objc
    fileprivate override init() {}

    @objc
    public func setStatus(_ valueParam: KeyBackupProtoRestoreResponseStatus) {
        proto.status = KeyBackupProtoRestoreResponseStatusUnwrap(valueParam)
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setToken(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.token = valueParam
    }

    public func setToken(_ valueParam: Data) {
        proto.token = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setData(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.data = valueParam
    }

    public func setData(_ valueParam: Data) {
        proto.data = valueParam
    }

    @objc
    public func setTries(_ valueParam: UInt32) {
        proto.tries = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> KeyBackupProtoRestoreResponse {
        return KeyBackupProtoRestoreResponse(proto)
    }

    @objc
    public func buildInfallibly() -> KeyBackupProtoRestoreResponse {
        return KeyBackupProtoRestoreResponse(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try KeyBackupProtoRestoreResponse(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension KeyBackupProtoRestoreResponse {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoRestoreResponseBuilder {
    @objc
    public func buildIgnoringErrors() -> KeyBackupProtoRestoreResponse? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - KeyBackupProtoDeleteRequest

@objc
public class KeyBackupProtoDeleteRequest: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: KeyBackupProtos_DeleteRequest

    @objc
    public var serviceID: Data? {
        guard hasServiceID else {
            return nil
        }
        return proto.serviceID
    }
    @objc
    public var hasServiceID: Bool {
        return proto.hasServiceID
    }

    @objc
    public var backupID: Data? {
        guard hasBackupID else {
            return nil
        }
        return proto.backupID
    }
    @objc
    public var hasBackupID: Bool {
        return proto.hasBackupID
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: KeyBackupProtos_DeleteRequest) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try KeyBackupProtos_DeleteRequest(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: KeyBackupProtos_DeleteRequest) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension KeyBackupProtoDeleteRequest {
    @objc
    public static func builder() -> KeyBackupProtoDeleteRequestBuilder {
        return KeyBackupProtoDeleteRequestBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> KeyBackupProtoDeleteRequestBuilder {
        let builder = KeyBackupProtoDeleteRequestBuilder()
        if let _value = serviceID {
            builder.setServiceID(_value)
        }
        if let _value = backupID {
            builder.setBackupID(_value)
        }
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class KeyBackupProtoDeleteRequestBuilder: NSObject {

    private var proto = KeyBackupProtos_DeleteRequest()

    @objc
    fileprivate override init() {}

    @objc
    @available(swift, obsoleted: 1.0)
    public func setServiceID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.serviceID = valueParam
    }

    public func setServiceID(_ valueParam: Data) {
        proto.serviceID = valueParam
    }

    @objc
    @available(swift, obsoleted: 1.0)
    public func setBackupID(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.backupID = valueParam
    }

    public func setBackupID(_ valueParam: Data) {
        proto.backupID = valueParam
    }

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> KeyBackupProtoDeleteRequest {
        return KeyBackupProtoDeleteRequest(proto)
    }

    @objc
    public func buildInfallibly() -> KeyBackupProtoDeleteRequest {
        return KeyBackupProtoDeleteRequest(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try KeyBackupProtoDeleteRequest(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension KeyBackupProtoDeleteRequest {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoDeleteRequestBuilder {
    @objc
    public func buildIgnoringErrors() -> KeyBackupProtoDeleteRequest? {
        return self.buildInfallibly()
    }
}

#endif

// MARK: - KeyBackupProtoDeleteResponse

@objc
public class KeyBackupProtoDeleteResponse: NSObject, Codable, NSSecureCoding {

    fileprivate let proto: KeyBackupProtos_DeleteResponse

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: KeyBackupProtos_DeleteResponse) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc
    public convenience init(serializedData: Data) throws {
        let proto = try KeyBackupProtos_DeleteResponse(serializedData: serializedData)
        self.init(proto)
    }

    fileprivate convenience init(_ proto: KeyBackupProtos_DeleteResponse) {
        self.init(proto: proto)
    }

    public required convenience init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public static var supportsSecureCoding: Bool { true }

    public required convenience init?(coder: NSCoder) {
        guard let serializedData = coder.decodeData() else { return nil }
        do {
            try self.init(serializedData: serializedData)
        } catch {
            owsFailDebug("Failed to decode serialized data \(error)")
            return nil
        }
    }

    public func encode(with coder: NSCoder) {
        do {
            coder.encode(try serializedData())
        } catch {
            owsFailDebug("Failed to encode serialized data \(error)")
        }
    }

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

extension KeyBackupProtoDeleteResponse {
    @objc
    public static func builder() -> KeyBackupProtoDeleteResponseBuilder {
        return KeyBackupProtoDeleteResponseBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc
    public func asBuilder() -> KeyBackupProtoDeleteResponseBuilder {
        let builder = KeyBackupProtoDeleteResponseBuilder()
        if let _value = unknownFields {
            builder.setUnknownFields(_value)
        }
        return builder
    }
}

@objc
public class KeyBackupProtoDeleteResponseBuilder: NSObject {

    private var proto = KeyBackupProtos_DeleteResponse()

    @objc
    fileprivate override init() {}

    public func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    @objc
    public func build() throws -> KeyBackupProtoDeleteResponse {
        return KeyBackupProtoDeleteResponse(proto)
    }

    @objc
    public func buildInfallibly() -> KeyBackupProtoDeleteResponse {
        return KeyBackupProtoDeleteResponse(proto)
    }

    @objc
    public func buildSerializedData() throws -> Data {
        return try KeyBackupProtoDeleteResponse(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension KeyBackupProtoDeleteResponse {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoDeleteResponseBuilder {
    @objc
    public func buildIgnoringErrors() -> KeyBackupProtoDeleteResponse? {
        return self.buildInfallibly()
    }
}

#endif
