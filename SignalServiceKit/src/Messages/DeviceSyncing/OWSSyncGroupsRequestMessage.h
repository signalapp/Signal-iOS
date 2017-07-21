//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSOutgoingSyncMessage.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSSyncGroupsRequestMessage : TSOutgoingMessage

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithThread:(nullable TSThread *)thread groupId:(NSData *)groupId;

@end

NS_ASSUME_NONNULL_END
