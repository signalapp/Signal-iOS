//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

// Any enum used by SDS extensions must be declared to conform
// to Codable and DatabaseValueConvertible.

extension TSOutgoingMessageState: Codable { }
extension TSOutgoingMessageState: DatabaseValueConvertible { }

extension RPRecentCallType: Codable { }
extension RPRecentCallType: DatabaseValueConvertible { }

extension TSErrorMessageType: Codable { }
extension TSErrorMessageType: DatabaseValueConvertible { }

extension TSInfoMessageType: Codable { }
extension TSInfoMessageType: DatabaseValueConvertible { }

extension OWSVerificationState: Codable { }
extension OWSVerificationState: DatabaseValueConvertible { }

extension TSGroupMetaMessage: Codable { }
extension TSGroupMetaMessage: DatabaseValueConvertible { }

extension TSAttachmentType: Codable { }
extension TSAttachmentType: DatabaseValueConvertible { }

extension TSAttachmentPointerType: Codable { }
extension TSAttachmentPointerType: DatabaseValueConvertible { }

extension TSAttachmentPointerState: Codable { }
extension TSAttachmentPointerState: DatabaseValueConvertible { }

extension SDSRecordType: Codable { }
extension SDSRecordType: DatabaseValueConvertible { }

extension TSRecentCallOfferType: Codable { }
extension TSRecentCallOfferType: DatabaseValueConvertible { }

extension TSPaymentCurrency: Codable { }
extension TSPaymentCurrency: DatabaseValueConvertible { }

extension TSPaymentState: Codable { }
extension TSPaymentState: DatabaseValueConvertible { }

extension TSPaymentFailure: Codable { }
extension TSPaymentFailure: DatabaseValueConvertible { }

extension TSPaymentType: Codable { }
extension TSPaymentType: DatabaseValueConvertible { }
