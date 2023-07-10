//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension OWSSyncRequestMessage {
    /// Convert a raw value of the returned enum to a strongly-typed case.
    ///
    /// ``SSKProtoSyncMessageRequestType`` has had cases deprecated and
    /// ultimately removed. However, those cases may have been persisted as
    /// a property on instances of this message - for example, when this message
    /// is serialized into a message send job record. Without this layer of
    /// indirection, we crash when trying to unwrap the persisted raw value of
    /// the deprecated case.
    ///
    /// - Returns
    /// The request type for this raw value. If no known request type matches,
    /// defaults to `.unknown`.
    @objc
    func requestType(rawValue: Int32) -> SSKProtoSyncMessageRequestType {
        return SSKProtoSyncMessageRequestType(rawValue: rawValue) ?? .unknown
    }
}
