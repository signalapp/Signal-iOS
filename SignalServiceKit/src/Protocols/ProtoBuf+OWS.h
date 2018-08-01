//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "SignalServiceKit-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

//@interface PBGeneratedMessageBuilder (OWS)
//
//@end

#pragma mark -

@interface SSKProtoDataMessageBuilder (OWS)

- (void)addLocalProfileKeyIfNecessary:(TSThread *)thread recipientId:(NSString *_Nullable)recipientId;
- (void)addLocalProfileKey;

@end

#pragma mark -

@interface SSKProtoCallMessageBuilder (OWS)

- (void)addLocalProfileKeyIfNecessary:(TSThread *)thread recipientId:(NSString *)recipientId;

@end

NS_ASSUME_NONNULL_END
