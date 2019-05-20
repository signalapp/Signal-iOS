//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "OWSMessageHandler.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSPrimaryStorage;
@class SSKProtoEnvelope;
@class TSMessage;
@class TSThread;
@class YapDatabaseReadWriteTransaction;

@interface OWSMessageManager : OWSMessageHandler

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)sharedManager;

- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;

// processEnvelope: can be called from any thread.
- (void)throws_processEnvelope:(SSKProtoEnvelope *)envelope
                 plaintextData:(NSData *_Nullable)plaintextData
               wasReceivedByUD:(BOOL)wasReceivedByUD
                   transaction:(YapDatabaseReadWriteTransaction *)transaction;

// This should be invoked by the main app when the app is ready.
- (void)startObserving;

+ (BOOL)messageHasRenderableContent:(TSMessage *)message;

@end

NS_ASSUME_NONNULL_END
