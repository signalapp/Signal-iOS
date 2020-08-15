//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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

extension SSKJobRecordStatus: Codable { }
extension SSKJobRecordStatus: DatabaseValueConvertible { }

extension SDSRecordType: Codable { }
extension SDSRecordType: DatabaseValueConvertible { }

extension TSRecentCallOfferType: Codable { }
extension TSRecentCallOfferType: DatabaseValueConvertible { }
