//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

@interface SignalRecipient : TSYapDatabaseObject

- (instancetype)initWithTextSecureIdentifier:(NSString *)textSecureIdentifier
                                       relay:(nullable NSString *)relay;

+ (instancetype)selfRecipient;
+ (nullable instancetype)recipientWithTextSecureIdentifier:(NSString *)textSecureIdentifier;
+ (nullable instancetype)recipientWithTextSecureIdentifier:(NSString *)textSecureIdentifier
                                           withTransaction:(YapDatabaseReadTransaction *)transaction;

- (void)addDevices:(NSSet *)set;

- (void)removeDevices:(NSSet *)set;

@property (nonatomic, nullable) NSString *relay;
@property (nonatomic) NSMutableOrderedSet *devices;

- (BOOL)supportsVoice;
// This property indicates support for both WebRTC audio and video calls.
- (BOOL)supportsWebRTC;

- (NSString *)recipientId;

- (NSComparisonResult)compare:(SignalRecipient *)other;

@end

NS_ASSUME_NONNULL_END
