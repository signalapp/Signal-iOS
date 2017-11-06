//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@class YapDatabaseReadTransaction;

@interface OWSSyncGroupsMessage : OWSOutgoingSyncMessage

- (NSData *)buildPlainTextAttachmentDataWithTransaction:(YapDatabaseReadTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
