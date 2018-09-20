//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageHandler.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSPrimaryStorage;
@class SSKProtoEnvelope;
@class TSThread;
@class YapDatabaseReadWriteTransaction;

@interface OWSMessageManager : OWSMessageHandler

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)sharedManager;

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;

// processEnvelope: can be called from any thread.
- (void)processEnvelope:(SSKProtoEnvelope *)envelope
          plaintextData:(NSData *_Nullable)plaintextData
            transaction:(YapDatabaseReadWriteTransaction *)transaction;

// This should be invoked by the main app when the app is ready.
- (void)startObserving;

@end

NS_ASSUME_NONNULL_END
