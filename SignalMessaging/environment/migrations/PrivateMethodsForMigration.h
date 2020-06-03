//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalServiceKit/OWSIdentityManager.h>
#import <SignalServiceKit/SSKPreKeyStore.h>
#import <SignalServiceKit/SSKSessionStore.h>
#import <SignalServiceKit/SSKSignedPreKeyStore.h>
#import <SignalServiceKit/TSAccountManager.h>

NS_ASSUME_NONNULL_BEGIN


// We need access to this for migration purposes

@class SDSKeyValueStore;

@interface SSKSessionStore (PrivateMethodsForMigration)

@property (nonatomic, readonly) SDSKeyValueStore *keyValueStore;

@end

@interface SSKPreKeyStore (PrivateMethodsForMigration)

@property (nonatomic, readonly) SDSKeyValueStore *keyStore;
@property (nonatomic, readonly) SDSKeyValueStore *metadataStore;

@end

@interface SSKSignedPreKeyStore (PrivateMethodsForMigration)

@property (nonatomic, readonly) SDSKeyValueStore *keyStore;
@property (nonatomic, readonly) SDSKeyValueStore *metadataStore;

@end

@interface OWSIdentityManager (PrivateMethodsForMigration)

@property (nonatomic, readonly) SDSKeyValueStore *ownIdentityKeyValueStore;
@property (nonatomic, readonly) SDSKeyValueStore *queuedVerificationStateSyncMessagesKeyValueStore;

@end

@interface TSAccountManager (PrivateMethodsForMigration)

@property (nonatomic, readonly) SDSKeyValueStore *keyValueStore;

@end


NS_ASSUME_NONNULL_END
