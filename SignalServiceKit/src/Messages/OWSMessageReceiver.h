//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSSignalServiceProtosEnvelope;
@class YapDatabase;

@interface OWSMessageReceiver : NSObject

+ (instancetype)sharedInstance;
+ (void)syncRegisterDatabaseExtension:(YapDatabase *)database;

- (void)handleReceivedEnvelope:(OWSSignalServiceProtosEnvelope *)envelope;

@end

NS_ASSUME_NONNULL_END
