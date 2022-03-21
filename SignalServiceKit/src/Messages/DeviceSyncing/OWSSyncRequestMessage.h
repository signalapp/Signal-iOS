//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSOutgoingSyncMessage.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(int32_t, SSKProtoSyncMessageRequestType);

@interface OWSSyncRequestMessage : OWSOutgoingSyncMessage

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSThread *)thread NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread
                   requestType:(SSKProtoSyncMessageRequestType)requestType NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
