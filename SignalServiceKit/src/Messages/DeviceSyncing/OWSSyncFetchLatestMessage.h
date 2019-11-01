//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(NSUInteger,
    OWSSyncFetchType) { OWSSyncFetchType_Unknown, OWSSyncFetchType_LocalProfile, OWSSyncFetchType_StorageManifest };

@interface OWSSyncFetchLatestMessage : OWSOutgoingSyncMessage

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSThread *)thread NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSThread *)thread fetchType:(OWSSyncFetchType)requestType;

@end

NS_ASSUME_NONNULL_END
