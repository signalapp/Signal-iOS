//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
public class KeyBackupProtoRequest: NSObject, Codable {

    // MARK: - KeyBackupProtoRequestBuilder

    @objc
    public class func builder() -> KeyBackupProtoRequestBuilder {
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
            return try KeyBackupProtoRequest(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try KeyBackupProtoRequest(proto).serializedData()
        }
    }

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
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: KeyBackupProtos_Request) throws {
        var backup: KeyBackupProtoBackupRequest?
        if proto.hasBackup {
            backup = try KeyBackupProtoBackupRequest(proto.backup)
        }

        var restore: KeyBackupProtoRestoreRequest?
        if proto.hasRestore {
            restore = try KeyBackupProtoRestoreRequest(proto.restore)
        }

        var delete: KeyBackupProtoDeleteRequest?
        if proto.hasDelete {
            delete = try KeyBackupProtoDeleteRequest(proto.delete)
        }

        // MARK: - Begin Validation Logic for KeyBackupProtoRequest -

        // MARK: - End Validation Logic for KeyBackupProtoRequest -

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

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension KeyBackupProtoRequest {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoRequest.KeyBackupProtoRequestBuilder {
    @objc
    public func buildIgnoringErrors() -> KeyBackupProtoRequest? {
        return try! self.build()
    }
}

#endif

// MARK: - KeyBackupProtoResponse

@objc
public class KeyBackupProtoResponse: NSObject, Codable {

    // MARK: - KeyBackupProtoResponseBuilder

    @objc
    public class func builder() -> KeyBackupProtoResponseBuilder {
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
            return try KeyBackupProtoResponse(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try KeyBackupProtoResponse(proto).serializedData()
        }
    }

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
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: KeyBackupProtos_Response) throws {
        var backup: KeyBackupProtoBackupResponse?
        if proto.hasBackup {
            backup = try KeyBackupProtoBackupResponse(proto.backup)
        }

        var restore: KeyBackupProtoRestoreResponse?
        if proto.hasRestore {
            restore = try KeyBackupProtoRestoreResponse(proto.restore)
        }

        var delete: KeyBackupProtoDeleteResponse?
        if proto.hasDelete {
            delete = try KeyBackupProtoDeleteResponse(proto.delete)
        }

        // MARK: - Begin Validation Logic for KeyBackupProtoResponse -

        // MARK: - End Validation Logic for KeyBackupProtoResponse -

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

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension KeyBackupProtoResponse {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoResponse.KeyBackupProtoResponseBuilder {
    @objc
    public func buildIgnoringErrors() -> KeyBackupProtoResponse? {
        return try! self.build()
    }
}

#endif

// MARK: - KeyBackupProtoBackupRequest

@objc
public class KeyBackupProtoBackupRequest: NSObject, Codable {

    // MARK: - KeyBackupProtoBackupRequestBuilder

    @objc
    public class func builder() -> KeyBackupProtoBackupRequestBuilder {
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
            return try KeyBackupProtoBackupRequest(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try KeyBackupProtoBackupRequest(proto).serializedData()
        }
    }

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
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: KeyBackupProtos_BackupRequest) throws {
        // MARK: - Begin Validation Logic for KeyBackupProtoBackupRequest -

        // MARK: - End Validation Logic for KeyBackupProtoBackupRequest -

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

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension KeyBackupProtoBackupRequest {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoBackupRequest.KeyBackupProtoBackupRequestBuilder {
    @objc
    public func buildIgnoringErrors() -> KeyBackupProtoBackupRequest? {
        return try! self.build()
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
public class KeyBackupProtoBackupResponse: NSObject, Codable {

    // MARK: - KeyBackupProtoBackupResponseBuilder

    @objc
    public class func builder() -> KeyBackupProtoBackupResponseBuilder {
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
            return try KeyBackupProtoBackupResponse(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try KeyBackupProtoBackupResponse(proto).serializedData()
        }
    }

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
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: KeyBackupProtos_BackupResponse) throws {
        // MARK: - Begin Validation Logic for KeyBackupProtoBackupResponse -

        // MARK: - End Validation Logic for KeyBackupProtoBackupResponse -

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

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension KeyBackupProtoBackupResponse {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoBackupResponse.KeyBackupProtoBackupResponseBuilder {
    @objc
    public func buildIgnoringErrors() -> KeyBackupProtoBackupResponse? {
        return try! self.build()
    }
}

#endif

// MARK: - KeyBackupProtoRestoreRequest

@objc
public class KeyBackupProtoRestoreRequest: NSObject, Codable {

    // MARK: - KeyBackupProtoRestoreRequestBuilder

    @objc
    public class func builder() -> KeyBackupProtoRestoreRequestBuilder {
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
            return try KeyBackupProtoRestoreRequest(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try KeyBackupProtoRestoreRequest(proto).serializedData()
        }
    }

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
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: KeyBackupProtos_RestoreRequest) throws {
        // MARK: - Begin Validation Logic for KeyBackupProtoRestoreRequest -

        // MARK: - End Validation Logic for KeyBackupProtoRestoreRequest -

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

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension KeyBackupProtoRestoreRequest {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoRestoreRequest.KeyBackupProtoRestoreRequestBuilder {
    @objc
    public func buildIgnoringErrors() -> KeyBackupProtoRestoreRequest? {
        return try! self.build()
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
public class KeyBackupProtoRestoreResponse: NSObject, Codable {

    // MARK: - KeyBackupProtoRestoreResponseBuilder

    @objc
    public class func builder() -> KeyBackupProtoRestoreResponseBuilder {
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
            return try KeyBackupProtoRestoreResponse(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try KeyBackupProtoRestoreResponse(proto).serializedData()
        }
    }

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
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: KeyBackupProtos_RestoreResponse) throws {
        // MARK: - Begin Validation Logic for KeyBackupProtoRestoreResponse -

        // MARK: - End Validation Logic for KeyBackupProtoRestoreResponse -

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

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension KeyBackupProtoRestoreResponse {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoRestoreResponse.KeyBackupProtoRestoreResponseBuilder {
    @objc
    public func buildIgnoringErrors() -> KeyBackupProtoRestoreResponse? {
        return try! self.build()
    }
}

#endif

// MARK: - KeyBackupProtoDeleteRequest

@objc
public class KeyBackupProtoDeleteRequest: NSObject, Codable {

    // MARK: - KeyBackupProtoDeleteRequestBuilder

    @objc
    public class func builder() -> KeyBackupProtoDeleteRequestBuilder {
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
            return try KeyBackupProtoDeleteRequest(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try KeyBackupProtoDeleteRequest(proto).serializedData()
        }
    }

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
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: KeyBackupProtos_DeleteRequest) throws {
        // MARK: - Begin Validation Logic for KeyBackupProtoDeleteRequest -

        // MARK: - End Validation Logic for KeyBackupProtoDeleteRequest -

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

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension KeyBackupProtoDeleteRequest {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoDeleteRequest.KeyBackupProtoDeleteRequestBuilder {
    @objc
    public func buildIgnoringErrors() -> KeyBackupProtoDeleteRequest? {
        return try! self.build()
    }
}

#endif

// MARK: - KeyBackupProtoDeleteResponse

@objc
public class KeyBackupProtoDeleteResponse: NSObject, Codable {

    // MARK: - KeyBackupProtoDeleteResponseBuilder

    @objc
    public class func builder() -> KeyBackupProtoDeleteResponseBuilder {
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
            return try KeyBackupProtoDeleteResponse(proto)
        }

        @objc
        public func buildSerializedData() throws -> Data {
            return try KeyBackupProtoDeleteResponse(proto).serializedData()
        }
    }

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
        try self.init(proto)
    }

    fileprivate convenience init(_ proto: KeyBackupProtos_DeleteResponse) throws {
        // MARK: - Begin Validation Logic for KeyBackupProtoDeleteResponse -

        // MARK: - End Validation Logic for KeyBackupProtoDeleteResponse -

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

    @objc
    public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension KeyBackupProtoDeleteResponse {
    @objc
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoDeleteResponse.KeyBackupProtoDeleteResponseBuilder {
    @objc
    public func buildIgnoringErrors() -> KeyBackupProtoDeleteResponse? {
        return try! self.build()
    }
}

#endif
