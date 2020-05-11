//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

typedef NS_CLOSED_ENUM(NSUInteger, OWSSyncRequestType) {
    OWSSyncRequestType_Unknown,
    OWSSyncRequestType_Contacts,
    OWSSyncRequestType_Groups,
    OWSSyncRequestType_Blocked,
    OWSSyncRequestType_Configuration,
    OWSSyncRequestType_Keys
};

@interface OWSSyncRequestMessage : OWSOutgoingSyncMessage

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithThread:(TSThread *)thread NS_UNAVAILABLE;
- (instancetype)initWithTimestamp:(uint64_t)timestamp thread:(TSThread *)thread NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread requestType:(OWSSyncRequestType)requestType NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
