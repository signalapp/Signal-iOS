//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SSKJobRecord.h"

NS_ASSUME_NONNULL_BEGIN

@class TSOutgoingMessage;

@interface SSKMessageSenderJobRecord : SSKJobRecord

@property (nonatomic, readonly, nullable) NSString *messageId;
@property (nonatomic, readonly, nullable) NSString *threadId;
@property (nonatomic, readonly, nullable) TSOutgoingMessage *invisibleMessage;
@property (nonatomic, readonly) BOOL removeMessageAfterSending;

- (nullable instancetype)initWithMessage:(TSOutgoingMessage *)message
               removeMessageAfterSending:(BOOL)removeMessageAfterSending
                                   label:(NSString *)label
                                   error:(NSError **)outError NS_DESIGNATED_INITIALIZER;

- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithLabel:(nullable NSString *)label NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
