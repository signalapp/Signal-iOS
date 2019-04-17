//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

@class OWSPrimaryStorage;
@class OWSStorage;
@class SSKProtoEnvelope;
@class YapDatabaseReadWriteTransaction;

@interface OWSMessageContentJob : TSYapDatabaseObject

@property (nonatomic, readonly) NSDate *createdAt;
@property (nonatomic, readonly) NSData *envelopeData;
@property (nonatomic, readonly, nullable) NSData *plaintextData;
@property (nonatomic, readonly) BOOL wasReceivedByUD;

- (instancetype)initWithEnvelopeData:(NSData *)envelopeData
                       plaintextData:(NSData *_Nullable)plaintextData
                     wasReceivedByUD:(BOOL)wasReceivedByUD NS_DESIGNATED_INITIALIZER;
- (nullable instancetype)initWithCoder:(NSCoder *)coder NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithUniqueId:(NSString *_Nullable)uniqueId NS_UNAVAILABLE;

// --- CODE GENERATION MARKER

// clang-format off

- (instancetype)initWithUniqueId:(NSString *)uniqueId
                       createdAt:(NSDate *)createdAt
                    envelopeData:(NSData *)envelopeData
                   plaintextData:(nullable NSData *)plaintextData
                 wasReceivedByUD:(BOOL)wasReceivedByUD
NS_SWIFT_NAME(init(uniqueId:createdAt:envelopeData:plaintextData:wasReceivedByUD:));

// clang-format on

// --- CODE GENERATION MARKER

@property (nonatomic, readonly, nullable) SSKProtoEnvelope *envelope;

@end

#pragma mark -

// This class is used to write incoming (decrypted, unprocessed)
// messages to a durable queue and then process them in batches,
// in the order in which they were received.
@interface OWSBatchMessageProcessor : NSObject

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithPrimaryStorage:(OWSPrimaryStorage *)primaryStorage NS_DESIGNATED_INITIALIZER;

+ (NSString *)databaseExtensionName;
+ (void)asyncRegisterDatabaseExtension:(OWSStorage *)storage;

- (void)enqueueEnvelopeData:(NSData *)envelopeData
              plaintextData:(NSData *_Nullable)plaintextData
            wasReceivedByUD:(BOOL)wasReceivedByUD
                transaction:(YapDatabaseReadWriteTransaction *)transaction;

@end

NS_ASSUME_NONNULL_END
