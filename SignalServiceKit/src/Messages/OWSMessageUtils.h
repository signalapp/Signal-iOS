//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class TSIncomingMessage;
@class TSOutgoingMessage;
@class TSQuotedMessage;
@class YapDatabaseReadWriteTransaction;

@interface OWSMessageUtils : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (nullable TSQuotedMessage *)quotedMessageForIncomingMessage:(TSIncomingMessage *)message
                                                  transaction:(YapDatabaseReadWriteTransaction *)transaction;

+ (nullable TSQuotedMessage *)quotedMessageForOutgoingMessage:(TSOutgoingMessage *)message
                                                  transaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
