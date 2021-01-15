//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

//*
// Copyright (C) 2014-2016 Open Whisper Systems
//
// Licensed according to the LICENSE file in this repository.

/// iOS - since we use a modern proto-compiler, we must specify
/// the legacy proto format.

import Foundation
import SwiftProtobuf

// If the compiler emits an error on this type, it is because this file
// was generated by a version of the `protoc` Swift plug-in that is
// incompatible with the version of SwiftProtobuf to which you are linking.
// Please ensure that you are building against the same version of the API
// that was used to generate this file.
private struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

struct ProvisioningProtos_ProvisioningUuid {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// @required
  var uuid: String {
    get {return _uuid ?? String()}
    set {_uuid = newValue}
  }
  /// Returns true if `uuid` has been explicitly set.
  var hasUuid: Bool {return self._uuid != nil}
  /// Clears the value of `uuid`. Subsequent reads from it will return its default value.
  mutating func clearUuid() {self._uuid = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _uuid: String?
}

struct ProvisioningProtos_ProvisionEnvelope {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// @required
  var publicKey: Data {
    get {return _publicKey ?? SwiftProtobuf.Internal.emptyData}
    set {_publicKey = newValue}
  }
  /// Returns true if `publicKey` has been explicitly set.
  var hasPublicKey: Bool {return self._publicKey != nil}
  /// Clears the value of `publicKey`. Subsequent reads from it will return its default value.
  mutating func clearPublicKey() {self._publicKey = nil}

  /// @required
  var body: Data {
    get {return _body ?? SwiftProtobuf.Internal.emptyData}
    set {_body = newValue}
  }
  /// Returns true if `body` has been explicitly set.
  var hasBody: Bool {return self._body != nil}
  /// Clears the value of `body`. Subsequent reads from it will return its default value.
  mutating func clearBody() {self._body = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _publicKey: Data?
  fileprivate var _body: Data?
}

struct ProvisioningProtos_ProvisionMessage {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  /// @required
  var identityKeyPublic: Data {
    get {return _identityKeyPublic ?? SwiftProtobuf.Internal.emptyData}
    set {_identityKeyPublic = newValue}
  }
  /// Returns true if `identityKeyPublic` has been explicitly set.
  var hasIdentityKeyPublic: Bool {return self._identityKeyPublic != nil}
  /// Clears the value of `identityKeyPublic`. Subsequent reads from it will return its default value.
  mutating func clearIdentityKeyPublic() {self._identityKeyPublic = nil}

  /// @required
  var identityKeyPrivate: Data {
    get {return _identityKeyPrivate ?? SwiftProtobuf.Internal.emptyData}
    set {_identityKeyPrivate = newValue}
  }
  /// Returns true if `identityKeyPrivate` has been explicitly set.
  var hasIdentityKeyPrivate: Bool {return self._identityKeyPrivate != nil}
  /// Clears the value of `identityKeyPrivate`. Subsequent reads from it will return its default value.
  mutating func clearIdentityKeyPrivate() {self._identityKeyPrivate = nil}

  var number: String {
    get {return _number ?? String()}
    set {_number = newValue}
  }
  /// Returns true if `number` has been explicitly set.
  var hasNumber: Bool {return self._number != nil}
  /// Clears the value of `number`. Subsequent reads from it will return its default value.
  mutating func clearNumber() {self._number = nil}

  var uuid: String {
    get {return _uuid ?? String()}
    set {_uuid = newValue}
  }
  /// Returns true if `uuid` has been explicitly set.
  var hasUuid: Bool {return self._uuid != nil}
  /// Clears the value of `uuid`. Subsequent reads from it will return its default value.
  mutating func clearUuid() {self._uuid = nil}

  /// @required
  var provisioningCode: String {
    get {return _provisioningCode ?? String()}
    set {_provisioningCode = newValue}
  }
  /// Returns true if `provisioningCode` has been explicitly set.
  var hasProvisioningCode: Bool {return self._provisioningCode != nil}
  /// Clears the value of `provisioningCode`. Subsequent reads from it will return its default value.
  mutating func clearProvisioningCode() {self._provisioningCode = nil}

  var userAgent: String {
    get {return _userAgent ?? String()}
    set {_userAgent = newValue}
  }
  /// Returns true if `userAgent` has been explicitly set.
  var hasUserAgent: Bool {return self._userAgent != nil}
  /// Clears the value of `userAgent`. Subsequent reads from it will return its default value.
  mutating func clearUserAgent() {self._userAgent = nil}

  /// @required
  var profileKey: Data {
    get {return _profileKey ?? SwiftProtobuf.Internal.emptyData}
    set {_profileKey = newValue}
  }
  /// Returns true if `profileKey` has been explicitly set.
  var hasProfileKey: Bool {return self._profileKey != nil}
  /// Clears the value of `profileKey`. Subsequent reads from it will return its default value.
  mutating func clearProfileKey() {self._profileKey = nil}

  var readReceipts: Bool {
    get {return _readReceipts ?? false}
    set {_readReceipts = newValue}
  }
  /// Returns true if `readReceipts` has been explicitly set.
  var hasReadReceipts: Bool {return self._readReceipts != nil}
  /// Clears the value of `readReceipts`. Subsequent reads from it will return its default value.
  mutating func clearReadReceipts() {self._readReceipts = nil}

  var provisioningVersion: UInt32 {
    get {return _provisioningVersion ?? 0}
    set {_provisioningVersion = newValue}
  }
  /// Returns true if `provisioningVersion` has been explicitly set.
  var hasProvisioningVersion: Bool {return self._provisioningVersion != nil}
  /// Clears the value of `provisioningVersion`. Subsequent reads from it will return its default value.
  mutating func clearProvisioningVersion() {self._provisioningVersion = nil}

  var unknownFields = SwiftProtobuf.UnknownStorage()

  init() {}

  fileprivate var _identityKeyPublic: Data?
  fileprivate var _identityKeyPrivate: Data?
  fileprivate var _number: String?
  fileprivate var _uuid: String?
  fileprivate var _provisioningCode: String?
  fileprivate var _userAgent: String?
  fileprivate var _profileKey: Data?
  fileprivate var _readReceipts: Bool?
  fileprivate var _provisioningVersion: UInt32?
}

// MARK: - Code below here is support for the SwiftProtobuf runtime.

private let _protobuf_package = "ProvisioningProtos"

extension ProvisioningProtos_ProvisioningUuid: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".ProvisioningUuid"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "uuid")
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try decoder.decodeSingularStringField(value: &self._uuid)
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if let v = self._uuid {
      try visitor.visitSingularStringField(value: v, fieldNumber: 1)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: ProvisioningProtos_ProvisioningUuid, rhs: ProvisioningProtos_ProvisioningUuid) -> Bool {
    if lhs._uuid != rhs._uuid {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension ProvisioningProtos_ProvisionEnvelope: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".ProvisionEnvelope"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "publicKey"),
    2: .same(proto: "body")
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try decoder.decodeSingularBytesField(value: &self._publicKey)
      case 2: try decoder.decodeSingularBytesField(value: &self._body)
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if let v = self._publicKey {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    }
    if let v = self._body {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 2)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: ProvisioningProtos_ProvisionEnvelope, rhs: ProvisioningProtos_ProvisionEnvelope) -> Bool {
    if lhs._publicKey != rhs._publicKey {return false}
    if lhs._body != rhs._body {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension ProvisioningProtos_ProvisionMessage: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  static let protoMessageName: String = _protobuf_package + ".ProvisionMessage"
  static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .same(proto: "identityKeyPublic"),
    2: .same(proto: "identityKeyPrivate"),
    3: .same(proto: "number"),
    8: .same(proto: "uuid"),
    4: .same(proto: "provisioningCode"),
    5: .same(proto: "userAgent"),
    6: .same(proto: "profileKey"),
    7: .same(proto: "readReceipts"),
    9: .same(proto: "provisioningVersion")
  ]

  mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      switch fieldNumber {
      case 1: try decoder.decodeSingularBytesField(value: &self._identityKeyPublic)
      case 2: try decoder.decodeSingularBytesField(value: &self._identityKeyPrivate)
      case 3: try decoder.decodeSingularStringField(value: &self._number)
      case 4: try decoder.decodeSingularStringField(value: &self._provisioningCode)
      case 5: try decoder.decodeSingularStringField(value: &self._userAgent)
      case 6: try decoder.decodeSingularBytesField(value: &self._profileKey)
      case 7: try decoder.decodeSingularBoolField(value: &self._readReceipts)
      case 8: try decoder.decodeSingularStringField(value: &self._uuid)
      case 9: try decoder.decodeSingularUInt32Field(value: &self._provisioningVersion)
      default: break
      }
    }
  }

  func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if let v = self._identityKeyPublic {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 1)
    }
    if let v = self._identityKeyPrivate {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 2)
    }
    if let v = self._number {
      try visitor.visitSingularStringField(value: v, fieldNumber: 3)
    }
    if let v = self._provisioningCode {
      try visitor.visitSingularStringField(value: v, fieldNumber: 4)
    }
    if let v = self._userAgent {
      try visitor.visitSingularStringField(value: v, fieldNumber: 5)
    }
    if let v = self._profileKey {
      try visitor.visitSingularBytesField(value: v, fieldNumber: 6)
    }
    if let v = self._readReceipts {
      try visitor.visitSingularBoolField(value: v, fieldNumber: 7)
    }
    if let v = self._uuid {
      try visitor.visitSingularStringField(value: v, fieldNumber: 8)
    }
    if let v = self._provisioningVersion {
      try visitor.visitSingularUInt32Field(value: v, fieldNumber: 9)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  static func ==(lhs: ProvisioningProtos_ProvisionMessage, rhs: ProvisioningProtos_ProvisionMessage) -> Bool {
    if lhs._identityKeyPublic != rhs._identityKeyPublic {return false}
    if lhs._identityKeyPrivate != rhs._identityKeyPrivate {return false}
    if lhs._number != rhs._number {return false}
    if lhs._uuid != rhs._uuid {return false}
    if lhs._provisioningCode != rhs._provisioningCode {return false}
    if lhs._userAgent != rhs._userAgent {return false}
    if lhs._profileKey != rhs._profileKey {return false}
    if lhs._readReceipts != rhs._readReceipts {return false}
    if lhs._provisioningVersion != rhs._provisioningVersion {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}
