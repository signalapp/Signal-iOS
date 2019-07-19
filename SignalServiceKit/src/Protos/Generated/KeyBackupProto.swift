//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

// WARNING: This code is generated. Only edit within the markers.

public enum KeyBackupProtoError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - KeyBackupProtoRequest

@objc public class KeyBackupProtoRequest: NSObject {

    // MARK: - KeyBackupProtoRequestBuilder

    @objc public class func builder() -> KeyBackupProtoRequestBuilder {
        return KeyBackupProtoRequestBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> KeyBackupProtoRequestBuilder {
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
        return builder
    }

    @objc public class KeyBackupProtoRequestBuilder: NSObject {

        private var proto = KeyBackupProtos_Request()

        @objc fileprivate override init() {}

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

        @objc public func build() throws -> KeyBackupProtoRequest {
            return try KeyBackupProtoRequest.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try KeyBackupProtoRequest.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: KeyBackupProtos_Request

    @objc public let backup: KeyBackupProtoBackupRequest?

    @objc public let restore: KeyBackupProtoRestoreRequest?

    @objc public let delete: KeyBackupProtoDeleteRequest?

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

    @objc public class func parseData(_ serializedData: Data) throws -> KeyBackupProtoRequest {
        let proto = try KeyBackupProtos_Request(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: KeyBackupProtos_Request) throws -> KeyBackupProtoRequest {
        var backup: KeyBackupProtoBackupRequest? = nil
        if proto.hasBackup {
            backup = try KeyBackupProtoBackupRequest.parseProto(proto.backup)
        }

        var restore: KeyBackupProtoRestoreRequest? = nil
        if proto.hasRestore {
            restore = try KeyBackupProtoRestoreRequest.parseProto(proto.restore)
        }

        var delete: KeyBackupProtoDeleteRequest? = nil
        if proto.hasDelete {
            delete = try KeyBackupProtoDeleteRequest.parseProto(proto.delete)
        }

        // MARK: - Begin Validation Logic for KeyBackupProtoRequest -

        // MARK: - End Validation Logic for KeyBackupProtoRequest -

        let result = KeyBackupProtoRequest(proto: proto,
                                           backup: backup,
                                           restore: restore,
                                           delete: delete)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension KeyBackupProtoRequest {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoRequest.KeyBackupProtoRequestBuilder {
    @objc public func buildIgnoringErrors() -> KeyBackupProtoRequest? {
        return try! self.build()
    }
}

#endif

// MARK: - KeyBackupProtoResponse

@objc public class KeyBackupProtoResponse: NSObject {

    // MARK: - KeyBackupProtoResponseBuilder

    @objc public class func builder() -> KeyBackupProtoResponseBuilder {
        return KeyBackupProtoResponseBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> KeyBackupProtoResponseBuilder {
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
        return builder
    }

    @objc public class KeyBackupProtoResponseBuilder: NSObject {

        private var proto = KeyBackupProtos_Response()

        @objc fileprivate override init() {}

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

        @objc public func build() throws -> KeyBackupProtoResponse {
            return try KeyBackupProtoResponse.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try KeyBackupProtoResponse.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: KeyBackupProtos_Response

    @objc public let backup: KeyBackupProtoBackupResponse?

    @objc public let restore: KeyBackupProtoRestoreResponse?

    @objc public let delete: KeyBackupProtoDeleteResponse?

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

    @objc public class func parseData(_ serializedData: Data) throws -> KeyBackupProtoResponse {
        let proto = try KeyBackupProtos_Response(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: KeyBackupProtos_Response) throws -> KeyBackupProtoResponse {
        var backup: KeyBackupProtoBackupResponse? = nil
        if proto.hasBackup {
            backup = try KeyBackupProtoBackupResponse.parseProto(proto.backup)
        }

        var restore: KeyBackupProtoRestoreResponse? = nil
        if proto.hasRestore {
            restore = try KeyBackupProtoRestoreResponse.parseProto(proto.restore)
        }

        var delete: KeyBackupProtoDeleteResponse? = nil
        if proto.hasDelete {
            delete = try KeyBackupProtoDeleteResponse.parseProto(proto.delete)
        }

        // MARK: - Begin Validation Logic for KeyBackupProtoResponse -

        // MARK: - End Validation Logic for KeyBackupProtoResponse -

        let result = KeyBackupProtoResponse(proto: proto,
                                            backup: backup,
                                            restore: restore,
                                            delete: delete)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension KeyBackupProtoResponse {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoResponse.KeyBackupProtoResponseBuilder {
    @objc public func buildIgnoringErrors() -> KeyBackupProtoResponse? {
        return try! self.build()
    }
}

#endif

// MARK: - KeyBackupProtoBackupRequest

@objc public class KeyBackupProtoBackupRequest: NSObject {

    // MARK: - KeyBackupProtoBackupRequestBuilder

    @objc public class func builder() -> KeyBackupProtoBackupRequestBuilder {
        return KeyBackupProtoBackupRequestBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> KeyBackupProtoBackupRequestBuilder {
        let builder = KeyBackupProtoBackupRequestBuilder()
        if let _value = serviceID {
            builder.setServiceID(_value)
        }
        if let _value = backupID {
            builder.setBackupID(_value)
        }
        if let _value = nonce {
            builder.setNonce(_value)
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
        return builder
    }

    @objc public class KeyBackupProtoBackupRequestBuilder: NSObject {

        private var proto = KeyBackupProtos_BackupRequest()

        @objc fileprivate override init() {}

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
        public func setNonce(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.nonce = valueParam
        }

        public func setNonce(_ valueParam: Data) {
            proto.nonce = valueParam
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

        @objc public func build() throws -> KeyBackupProtoBackupRequest {
            return try KeyBackupProtoBackupRequest.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try KeyBackupProtoBackupRequest.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: KeyBackupProtos_BackupRequest

    @objc public var serviceID: Data? {
        guard proto.hasServiceID else {
            return nil
        }
        return proto.serviceID
    }
    @objc public var hasServiceID: Bool {
        return proto.hasServiceID
    }

    @objc public var backupID: Data? {
        guard proto.hasBackupID else {
            return nil
        }
        return proto.backupID
    }
    @objc public var hasBackupID: Bool {
        return proto.hasBackupID
    }

    @objc public var nonce: Data? {
        guard proto.hasNonce else {
            return nil
        }
        return proto.nonce
    }
    @objc public var hasNonce: Bool {
        return proto.hasNonce
    }

    @objc public var validFrom: UInt64 {
        return proto.validFrom
    }
    @objc public var hasValidFrom: Bool {
        return proto.hasValidFrom
    }

    @objc public var data: Data? {
        guard proto.hasData else {
            return nil
        }
        return proto.data
    }
    @objc public var hasData: Bool {
        return proto.hasData
    }

    @objc public var pin: Data? {
        guard proto.hasPin else {
            return nil
        }
        return proto.pin
    }
    @objc public var hasPin: Bool {
        return proto.hasPin
    }

    @objc public var tries: UInt32 {
        return proto.tries
    }
    @objc public var hasTries: Bool {
        return proto.hasTries
    }

    private init(proto: KeyBackupProtos_BackupRequest) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> KeyBackupProtoBackupRequest {
        let proto = try KeyBackupProtos_BackupRequest(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: KeyBackupProtos_BackupRequest) throws -> KeyBackupProtoBackupRequest {
        // MARK: - Begin Validation Logic for KeyBackupProtoBackupRequest -

        // MARK: - End Validation Logic for KeyBackupProtoBackupRequest -

        let result = KeyBackupProtoBackupRequest(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension KeyBackupProtoBackupRequest {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoBackupRequest.KeyBackupProtoBackupRequestBuilder {
    @objc public func buildIgnoringErrors() -> KeyBackupProtoBackupRequest? {
        return try! self.build()
    }
}

#endif

// MARK: - KeyBackupProtoBackupResponse

@objc public class KeyBackupProtoBackupResponse: NSObject {

    // MARK: - KeyBackupProtoBackupResponseStatus

    @objc public enum KeyBackupProtoBackupResponseStatus: Int32 {
        case ok = 1
        case nonceMismatch = 2
        case notYetValid = 3
    }

    private class func KeyBackupProtoBackupResponseStatusWrap(_ value: KeyBackupProtos_BackupResponse.Status) -> KeyBackupProtoBackupResponseStatus {
        switch value {
        case .ok: return .ok
        case .nonceMismatch: return .nonceMismatch
        case .notYetValid: return .notYetValid
        }
    }

    private class func KeyBackupProtoBackupResponseStatusUnwrap(_ value: KeyBackupProtoBackupResponseStatus) -> KeyBackupProtos_BackupResponse.Status {
        switch value {
        case .ok: return .ok
        case .nonceMismatch: return .nonceMismatch
        case .notYetValid: return .notYetValid
        }
    }

    // MARK: - KeyBackupProtoBackupResponseBuilder

    @objc public class func builder() -> KeyBackupProtoBackupResponseBuilder {
        return KeyBackupProtoBackupResponseBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> KeyBackupProtoBackupResponseBuilder {
        let builder = KeyBackupProtoBackupResponseBuilder()
        if let _value = status {
            builder.setStatus(_value)
        }
        if let _value = nonce {
            builder.setNonce(_value)
        }
        return builder
    }

    @objc public class KeyBackupProtoBackupResponseBuilder: NSObject {

        private var proto = KeyBackupProtos_BackupResponse()

        @objc fileprivate override init() {}

        @objc
        public func setStatus(_ valueParam: KeyBackupProtoBackupResponseStatus) {
            proto.status = KeyBackupProtoBackupResponseStatusUnwrap(valueParam)
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setNonce(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.nonce = valueParam
        }

        public func setNonce(_ valueParam: Data) {
            proto.nonce = valueParam
        }

        @objc public func build() throws -> KeyBackupProtoBackupResponse {
            return try KeyBackupProtoBackupResponse.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try KeyBackupProtoBackupResponse.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: KeyBackupProtos_BackupResponse

    public var status: KeyBackupProtoBackupResponseStatus? {
        guard proto.hasStatus else {
            return nil
        }
        return KeyBackupProtoBackupResponse.KeyBackupProtoBackupResponseStatusWrap(proto.status)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc public var unwrappedStatus: KeyBackupProtoBackupResponseStatus {
        if !hasStatus {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: BackupResponse.status.")
        }
        return KeyBackupProtoBackupResponse.KeyBackupProtoBackupResponseStatusWrap(proto.status)
    }
    @objc public var hasStatus: Bool {
        return proto.hasStatus
    }

    @objc public var nonce: Data? {
        guard proto.hasNonce else {
            return nil
        }
        return proto.nonce
    }
    @objc public var hasNonce: Bool {
        return proto.hasNonce
    }

    private init(proto: KeyBackupProtos_BackupResponse) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> KeyBackupProtoBackupResponse {
        let proto = try KeyBackupProtos_BackupResponse(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: KeyBackupProtos_BackupResponse) throws -> KeyBackupProtoBackupResponse {
        // MARK: - Begin Validation Logic for KeyBackupProtoBackupResponse -

        // MARK: - End Validation Logic for KeyBackupProtoBackupResponse -

        let result = KeyBackupProtoBackupResponse(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension KeyBackupProtoBackupResponse {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoBackupResponse.KeyBackupProtoBackupResponseBuilder {
    @objc public func buildIgnoringErrors() -> KeyBackupProtoBackupResponse? {
        return try! self.build()
    }
}

#endif

// MARK: - KeyBackupProtoRestoreRequest

@objc public class KeyBackupProtoRestoreRequest: NSObject {

    // MARK: - KeyBackupProtoRestoreRequestBuilder

    @objc public class func builder() -> KeyBackupProtoRestoreRequestBuilder {
        return KeyBackupProtoRestoreRequestBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> KeyBackupProtoRestoreRequestBuilder {
        let builder = KeyBackupProtoRestoreRequestBuilder()
        if let _value = serviceID {
            builder.setServiceID(_value)
        }
        if let _value = backupID {
            builder.setBackupID(_value)
        }
        if let _value = nonce {
            builder.setNonce(_value)
        }
        if hasValidFrom {
            builder.setValidFrom(validFrom)
        }
        if let _value = pin {
            builder.setPin(_value)
        }
        return builder
    }

    @objc public class KeyBackupProtoRestoreRequestBuilder: NSObject {

        private var proto = KeyBackupProtos_RestoreRequest()

        @objc fileprivate override init() {}

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
        public func setNonce(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.nonce = valueParam
        }

        public func setNonce(_ valueParam: Data) {
            proto.nonce = valueParam
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

        @objc public func build() throws -> KeyBackupProtoRestoreRequest {
            return try KeyBackupProtoRestoreRequest.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try KeyBackupProtoRestoreRequest.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: KeyBackupProtos_RestoreRequest

    @objc public var serviceID: Data? {
        guard proto.hasServiceID else {
            return nil
        }
        return proto.serviceID
    }
    @objc public var hasServiceID: Bool {
        return proto.hasServiceID
    }

    @objc public var backupID: Data? {
        guard proto.hasBackupID else {
            return nil
        }
        return proto.backupID
    }
    @objc public var hasBackupID: Bool {
        return proto.hasBackupID
    }

    @objc public var nonce: Data? {
        guard proto.hasNonce else {
            return nil
        }
        return proto.nonce
    }
    @objc public var hasNonce: Bool {
        return proto.hasNonce
    }

    @objc public var validFrom: UInt64 {
        return proto.validFrom
    }
    @objc public var hasValidFrom: Bool {
        return proto.hasValidFrom
    }

    @objc public var pin: Data? {
        guard proto.hasPin else {
            return nil
        }
        return proto.pin
    }
    @objc public var hasPin: Bool {
        return proto.hasPin
    }

    private init(proto: KeyBackupProtos_RestoreRequest) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> KeyBackupProtoRestoreRequest {
        let proto = try KeyBackupProtos_RestoreRequest(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: KeyBackupProtos_RestoreRequest) throws -> KeyBackupProtoRestoreRequest {
        // MARK: - Begin Validation Logic for KeyBackupProtoRestoreRequest -

        // MARK: - End Validation Logic for KeyBackupProtoRestoreRequest -

        let result = KeyBackupProtoRestoreRequest(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension KeyBackupProtoRestoreRequest {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoRestoreRequest.KeyBackupProtoRestoreRequestBuilder {
    @objc public func buildIgnoringErrors() -> KeyBackupProtoRestoreRequest? {
        return try! self.build()
    }
}

#endif

// MARK: - KeyBackupProtoRestoreResponse

@objc public class KeyBackupProtoRestoreResponse: NSObject {

    // MARK: - KeyBackupProtoRestoreResponseStatus

    @objc public enum KeyBackupProtoRestoreResponseStatus: Int32 {
        case ok = 1
        case nonceMismatch = 2
        case notYetValid = 3
        case missing = 4
        case pinMismatch = 5
    }

    private class func KeyBackupProtoRestoreResponseStatusWrap(_ value: KeyBackupProtos_RestoreResponse.Status) -> KeyBackupProtoRestoreResponseStatus {
        switch value {
        case .ok: return .ok
        case .nonceMismatch: return .nonceMismatch
        case .notYetValid: return .notYetValid
        case .missing: return .missing
        case .pinMismatch: return .pinMismatch
        }
    }

    private class func KeyBackupProtoRestoreResponseStatusUnwrap(_ value: KeyBackupProtoRestoreResponseStatus) -> KeyBackupProtos_RestoreResponse.Status {
        switch value {
        case .ok: return .ok
        case .nonceMismatch: return .nonceMismatch
        case .notYetValid: return .notYetValid
        case .missing: return .missing
        case .pinMismatch: return .pinMismatch
        }
    }

    // MARK: - KeyBackupProtoRestoreResponseBuilder

    @objc public class func builder() -> KeyBackupProtoRestoreResponseBuilder {
        return KeyBackupProtoRestoreResponseBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> KeyBackupProtoRestoreResponseBuilder {
        let builder = KeyBackupProtoRestoreResponseBuilder()
        if let _value = status {
            builder.setStatus(_value)
        }
        if let _value = nonce {
            builder.setNonce(_value)
        }
        if let _value = data {
            builder.setData(_value)
        }
        if hasTries {
            builder.setTries(tries)
        }
        return builder
    }

    @objc public class KeyBackupProtoRestoreResponseBuilder: NSObject {

        private var proto = KeyBackupProtos_RestoreResponse()

        @objc fileprivate override init() {}

        @objc
        public func setStatus(_ valueParam: KeyBackupProtoRestoreResponseStatus) {
            proto.status = KeyBackupProtoRestoreResponseStatusUnwrap(valueParam)
        }

        @objc
        @available(swift, obsoleted: 1.0)
        public func setNonce(_ valueParam: Data?) {
            guard let valueParam = valueParam else { return }
            proto.nonce = valueParam
        }

        public func setNonce(_ valueParam: Data) {
            proto.nonce = valueParam
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

        @objc public func build() throws -> KeyBackupProtoRestoreResponse {
            return try KeyBackupProtoRestoreResponse.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try KeyBackupProtoRestoreResponse.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: KeyBackupProtos_RestoreResponse

    public var status: KeyBackupProtoRestoreResponseStatus? {
        guard proto.hasStatus else {
            return nil
        }
        return KeyBackupProtoRestoreResponse.KeyBackupProtoRestoreResponseStatusWrap(proto.status)
    }
    // This "unwrapped" accessor should only be used if the "has value" accessor has already been checked.
    @objc public var unwrappedStatus: KeyBackupProtoRestoreResponseStatus {
        if !hasStatus {
            // TODO: We could make this a crashing assert.
            owsFailDebug("Unsafe unwrap of missing optional: RestoreResponse.status.")
        }
        return KeyBackupProtoRestoreResponse.KeyBackupProtoRestoreResponseStatusWrap(proto.status)
    }
    @objc public var hasStatus: Bool {
        return proto.hasStatus
    }

    @objc public var nonce: Data? {
        guard proto.hasNonce else {
            return nil
        }
        return proto.nonce
    }
    @objc public var hasNonce: Bool {
        return proto.hasNonce
    }

    @objc public var data: Data? {
        guard proto.hasData else {
            return nil
        }
        return proto.data
    }
    @objc public var hasData: Bool {
        return proto.hasData
    }

    @objc public var tries: UInt32 {
        return proto.tries
    }
    @objc public var hasTries: Bool {
        return proto.hasTries
    }

    private init(proto: KeyBackupProtos_RestoreResponse) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> KeyBackupProtoRestoreResponse {
        let proto = try KeyBackupProtos_RestoreResponse(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: KeyBackupProtos_RestoreResponse) throws -> KeyBackupProtoRestoreResponse {
        // MARK: - Begin Validation Logic for KeyBackupProtoRestoreResponse -

        // MARK: - End Validation Logic for KeyBackupProtoRestoreResponse -

        let result = KeyBackupProtoRestoreResponse(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension KeyBackupProtoRestoreResponse {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoRestoreResponse.KeyBackupProtoRestoreResponseBuilder {
    @objc public func buildIgnoringErrors() -> KeyBackupProtoRestoreResponse? {
        return try! self.build()
    }
}

#endif

// MARK: - KeyBackupProtoDeleteRequest

@objc public class KeyBackupProtoDeleteRequest: NSObject {

    // MARK: - KeyBackupProtoDeleteRequestBuilder

    @objc public class func builder() -> KeyBackupProtoDeleteRequestBuilder {
        return KeyBackupProtoDeleteRequestBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> KeyBackupProtoDeleteRequestBuilder {
        let builder = KeyBackupProtoDeleteRequestBuilder()
        if let _value = serviceID {
            builder.setServiceID(_value)
        }
        if let _value = backupID {
            builder.setBackupID(_value)
        }
        return builder
    }

    @objc public class KeyBackupProtoDeleteRequestBuilder: NSObject {

        private var proto = KeyBackupProtos_DeleteRequest()

        @objc fileprivate override init() {}

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

        @objc public func build() throws -> KeyBackupProtoDeleteRequest {
            return try KeyBackupProtoDeleteRequest.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try KeyBackupProtoDeleteRequest.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: KeyBackupProtos_DeleteRequest

    @objc public var serviceID: Data? {
        guard proto.hasServiceID else {
            return nil
        }
        return proto.serviceID
    }
    @objc public var hasServiceID: Bool {
        return proto.hasServiceID
    }

    @objc public var backupID: Data? {
        guard proto.hasBackupID else {
            return nil
        }
        return proto.backupID
    }
    @objc public var hasBackupID: Bool {
        return proto.hasBackupID
    }

    private init(proto: KeyBackupProtos_DeleteRequest) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> KeyBackupProtoDeleteRequest {
        let proto = try KeyBackupProtos_DeleteRequest(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: KeyBackupProtos_DeleteRequest) throws -> KeyBackupProtoDeleteRequest {
        // MARK: - Begin Validation Logic for KeyBackupProtoDeleteRequest -

        // MARK: - End Validation Logic for KeyBackupProtoDeleteRequest -

        let result = KeyBackupProtoDeleteRequest(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension KeyBackupProtoDeleteRequest {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoDeleteRequest.KeyBackupProtoDeleteRequestBuilder {
    @objc public func buildIgnoringErrors() -> KeyBackupProtoDeleteRequest? {
        return try! self.build()
    }
}

#endif

// MARK: - KeyBackupProtoDeleteResponse

@objc public class KeyBackupProtoDeleteResponse: NSObject {

    // MARK: - KeyBackupProtoDeleteResponseBuilder

    @objc public class func builder() -> KeyBackupProtoDeleteResponseBuilder {
        return KeyBackupProtoDeleteResponseBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    @objc public func asBuilder() -> KeyBackupProtoDeleteResponseBuilder {
        let builder = KeyBackupProtoDeleteResponseBuilder()
        return builder
    }

    @objc public class KeyBackupProtoDeleteResponseBuilder: NSObject {

        private var proto = KeyBackupProtos_DeleteResponse()

        @objc fileprivate override init() {}

        @objc public func build() throws -> KeyBackupProtoDeleteResponse {
            return try KeyBackupProtoDeleteResponse.parseProto(proto)
        }

        @objc public func buildSerializedData() throws -> Data {
            return try KeyBackupProtoDeleteResponse.parseProto(proto).serializedData()
        }
    }

    fileprivate let proto: KeyBackupProtos_DeleteResponse

    private init(proto: KeyBackupProtos_DeleteResponse) {
        self.proto = proto
    }

    @objc
    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    @objc public class func parseData(_ serializedData: Data) throws -> KeyBackupProtoDeleteResponse {
        let proto = try KeyBackupProtos_DeleteResponse(serializedData: serializedData)
        return try parseProto(proto)
    }

    fileprivate class func parseProto(_ proto: KeyBackupProtos_DeleteResponse) throws -> KeyBackupProtoDeleteResponse {
        // MARK: - Begin Validation Logic for KeyBackupProtoDeleteResponse -

        // MARK: - End Validation Logic for KeyBackupProtoDeleteResponse -

        let result = KeyBackupProtoDeleteResponse(proto: proto)
        return result
    }

    @objc public override var debugDescription: String {
        return "\(proto)"
    }
}

#if DEBUG

extension KeyBackupProtoDeleteResponse {
    @objc public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension KeyBackupProtoDeleteResponse.KeyBackupProtoDeleteResponseBuilder {
    @objc public func buildIgnoringErrors() -> KeyBackupProtoDeleteResponse? {
        return try! self.build()
    }
}

#endif
