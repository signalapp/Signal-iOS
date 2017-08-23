//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@class TSThread;

@interface PBGeneratedMessageBuilder (OWS)

@end

#pragma mark -

@interface OWSSignalServiceProtosDataMessageBuilder (OWS)

- (void)addLocalProfileKeyIfNecessary:(TSThread *)thread recipientId:(NSString *_Nullable)recipientId;

@end

#pragma mark -

@interface OWSSignalServiceProtosCallMessageBuilder (OWS)

- (void)addLocalProfileKeyIfNecessary:(TSThread *)thread recipientId:(NSString *)recipientId;

@end

#pragma mark -

@interface OWSSignalServiceProtosSyncMessageBuilder (OWS)

- (void)addLocalProfileKey;

@end

#pragma mark -

@interface OWSSignalServiceProtosNullMessageBuilder (OWS)

- (void)addLocalProfileKeyIfNecessary:(TSThread *)thread recipientId:(NSString *)recipientId;

@end

NS_ASSUME_NONNULL_END
