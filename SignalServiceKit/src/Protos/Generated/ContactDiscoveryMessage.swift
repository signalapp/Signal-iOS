//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit
import SwiftProtobuf

// WARNING: This code is generated. Only edit within the markers.

public enum ContactDiscoveryMessageError: Error {
    case invalidProtobuf(description: String)
}

// MARK: - ContactDiscoveryMessageClientRequest

public struct ContactDiscoveryMessageClientRequest: Codable, CustomDebugStringConvertible {

    fileprivate let proto: ContactDiscoveryMessages_ClientRequest

    public var aciUakPairs: Data? {
        guard hasAciUakPairs else {
            return nil
        }
        return proto.aciUakPairs
    }
    public var hasAciUakPairs: Bool {
        return !proto.aciUakPairs.isEmpty
    }

    public var prevE164List: Data? {
        guard hasPrevE164List else {
            return nil
        }
        return proto.prevE164List
    }
    public var hasPrevE164List: Bool {
        return !proto.prevE164List.isEmpty
    }

    public var newE164List: Data? {
        guard hasNewE164List else {
            return nil
        }
        return proto.newE164List
    }
    public var hasNewE164List: Bool {
        return !proto.newE164List.isEmpty
    }

    public var discardE164List: Data? {
        guard hasDiscardE164List else {
            return nil
        }
        return proto.discardE164List
    }
    public var hasDiscardE164List: Bool {
        return !proto.discardE164List.isEmpty
    }

    public var moreComing: Bool {
        return proto.moreComing
    }
    public var hasMoreComing: Bool {
        return true
    }

    public var token: Data? {
        guard hasToken else {
            return nil
        }
        return proto.token
    }
    public var hasToken: Bool {
        return !proto.token.isEmpty
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: ContactDiscoveryMessages_ClientRequest) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try ContactDiscoveryMessages_ClientRequest(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: ContactDiscoveryMessages_ClientRequest) throws {
        // MARK: - Begin Validation Logic for ContactDiscoveryMessageClientRequest -

        // MARK: - End Validation Logic for ContactDiscoveryMessageClientRequest -

        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension ContactDiscoveryMessageClientRequest {
    public static func builder() -> ContactDiscoveryMessageClientRequestBuilder {
        return ContactDiscoveryMessageClientRequestBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> ContactDiscoveryMessageClientRequestBuilder {
        var builder = ContactDiscoveryMessageClientRequestBuilder()
        if let _value = aciUakPairs {
            builder.setAciUakPairs(_value)
        }
        if let _value = prevE164List {
            builder.setPrevE164List(_value)
        }
        if let _value = newE164List {
            builder.setNewE164List(_value)
        }
        if let _value = discardE164List {
            builder.setDiscardE164List(_value)
        }
        if hasMoreComing {
            builder.setMoreComing(moreComing)
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

public struct ContactDiscoveryMessageClientRequestBuilder {

    private var proto = ContactDiscoveryMessages_ClientRequest()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setAciUakPairs(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.aciUakPairs = valueParam
    }

    public mutating func setAciUakPairs(_ valueParam: Data) {
        proto.aciUakPairs = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setPrevE164List(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.prevE164List = valueParam
    }

    public mutating func setPrevE164List(_ valueParam: Data) {
        proto.prevE164List = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setNewE164List(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.newE164List = valueParam
    }

    public mutating func setNewE164List(_ valueParam: Data) {
        proto.newE164List = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setDiscardE164List(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.discardE164List = valueParam
    }

    public mutating func setDiscardE164List(_ valueParam: Data) {
        proto.discardE164List = valueParam
    }

    public mutating func setMoreComing(_ valueParam: Bool) {
        proto.moreComing = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setToken(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.token = valueParam
    }

    public mutating func setToken(_ valueParam: Data) {
        proto.token = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> ContactDiscoveryMessageClientRequest {
        return try ContactDiscoveryMessageClientRequest(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try ContactDiscoveryMessageClientRequest(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension ContactDiscoveryMessageClientRequest {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension ContactDiscoveryMessageClientRequestBuilder {
    public func buildIgnoringErrors() -> ContactDiscoveryMessageClientRequest? {
        return try! self.build()
    }
}

#endif

// MARK: - ContactDiscoveryMessageClientResponse

public struct ContactDiscoveryMessageClientResponse: Codable, CustomDebugStringConvertible {

    fileprivate let proto: ContactDiscoveryMessages_ClientResponse

    public var e164PniAciTriples: Data? {
        guard hasE164PniAciTriples else {
            return nil
        }
        return proto.e164PniAciTriples
    }
    public var hasE164PniAciTriples: Bool {
        return !proto.e164PniAciTriples.isEmpty
    }

    public var retryAfterSecs: Int32? {
        guard hasRetryAfterSecs else {
            return nil
        }
        return proto.retryAfterSecs
    }
    public var hasRetryAfterSecs: Bool {
        return true
    }

    public var token: Data? {
        guard hasToken else {
            return nil
        }
        return proto.token
    }
    public var hasToken: Bool {
        return !proto.token.isEmpty
    }

    public var hasUnknownFields: Bool {
        return !proto.unknownFields.data.isEmpty
    }
    public var unknownFields: SwiftProtobuf.UnknownStorage? {
        guard hasUnknownFields else { return nil }
        return proto.unknownFields
    }

    private init(proto: ContactDiscoveryMessages_ClientResponse) {
        self.proto = proto
    }

    public func serializedData() throws -> Data {
        return try self.proto.serializedData()
    }

    public init(serializedData: Data) throws {
        let proto = try ContactDiscoveryMessages_ClientResponse(serializedData: serializedData)
        try self.init(proto)
    }

    fileprivate init(_ proto: ContactDiscoveryMessages_ClientResponse) throws {
        // MARK: - Begin Validation Logic for ContactDiscoveryMessageClientResponse -

        // MARK: - End Validation Logic for ContactDiscoveryMessageClientResponse -

        self.init(proto: proto)
    }

    public init(from decoder: Swift.Decoder) throws {
        let singleValueContainer = try decoder.singleValueContainer()
        let serializedData = try singleValueContainer.decode(Data.self)
        try self.init(serializedData: serializedData)
    }
    public func encode(to encoder: Swift.Encoder) throws {
        var singleValueContainer = encoder.singleValueContainer()
        try singleValueContainer.encode(try serializedData())
    }

    public var debugDescription: String {
        return "\(proto)"
    }
}

extension ContactDiscoveryMessageClientResponse {
    public static func builder() -> ContactDiscoveryMessageClientResponseBuilder {
        return ContactDiscoveryMessageClientResponseBuilder()
    }

    // asBuilder() constructs a builder that reflects the proto's contents.
    public func asBuilder() -> ContactDiscoveryMessageClientResponseBuilder {
        var builder = ContactDiscoveryMessageClientResponseBuilder()
        if let _value = e164PniAciTriples {
            builder.setE164PniAciTriples(_value)
        }
        if let _value = retryAfterSecs {
            builder.setRetryAfterSecs(_value)
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

public struct ContactDiscoveryMessageClientResponseBuilder {

    private var proto = ContactDiscoveryMessages_ClientResponse()

    fileprivate init() {}

    @available(swift, obsoleted: 1.0)
    public mutating func setE164PniAciTriples(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.e164PniAciTriples = valueParam
    }

    public mutating func setE164PniAciTriples(_ valueParam: Data) {
        proto.e164PniAciTriples = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setRetryAfterSecs(_ valueParam: Int32?) {
        guard let valueParam = valueParam else { return }
        proto.retryAfterSecs = valueParam
    }

    public mutating func setRetryAfterSecs(_ valueParam: Int32) {
        proto.retryAfterSecs = valueParam
    }

    @available(swift, obsoleted: 1.0)
    public mutating func setToken(_ valueParam: Data?) {
        guard let valueParam = valueParam else { return }
        proto.token = valueParam
    }

    public mutating func setToken(_ valueParam: Data) {
        proto.token = valueParam
    }

    public mutating func setUnknownFields(_ unknownFields: SwiftProtobuf.UnknownStorage) {
        proto.unknownFields = unknownFields
    }

    public func build() throws -> ContactDiscoveryMessageClientResponse {
        return try ContactDiscoveryMessageClientResponse(proto)
    }

    public func buildSerializedData() throws -> Data {
        return try ContactDiscoveryMessageClientResponse(proto).serializedData()
    }
}

#if TESTABLE_BUILD

extension ContactDiscoveryMessageClientResponse {
    public func serializedDataIgnoringErrors() -> Data? {
        return try! self.serializedData()
    }
}

extension ContactDiscoveryMessageClientResponseBuilder {
    public func buildIgnoringErrors() -> ContactDiscoveryMessageClientResponse? {
        return try! self.build()
    }
}

#endif
