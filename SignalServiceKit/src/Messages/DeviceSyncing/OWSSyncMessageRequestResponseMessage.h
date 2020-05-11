//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(NSUInteger, OWSSyncMessageRequestResponseType) { OWSSyncMessageRequestResponseType_Accept,
    OWSSyncMessageRequestResponseType_Delete,
    OWSSyncMessageRequestResponseType_Block,
    OWSSyncMessageRequestResponseType_BlockAndDelete };

@interface OWSSyncMessageRequestResponseMessage : OWSOutgoingSyncMessage

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSThread *)thread NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread
                  responseType:(OWSSyncMessageRequestResponseType)responseType NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
