//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <AxolotlKit/PreKeyStore.h>

NS_ASSUME_NONNULL_BEGIN

@class SDSKeyValueStore;

@interface SSKPreKeyStore : NSObject <PreKeyStore>

@property (nonatomic, readonly) SDSKeyValueStore *keyStore;

- (NSArray<PreKeyRecord *> *)generatePreKeyRecords;
- (void)storePreKeyRecords:(NSArray<PreKeyRecord *> *)preKeyRecords NS_SWIFT_NAME(storePreKeyRecords(_:));

@end

NS_ASSUME_NONNULL_END
