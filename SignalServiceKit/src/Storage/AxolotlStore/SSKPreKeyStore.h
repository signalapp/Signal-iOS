//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import <AxolotlKit/PreKeyStore.h>

NS_ASSUME_NONNULL_BEGIN

@class SDSAnyWriteTransaction;
@class SDSKeyValueStore;

@interface SSKPreKeyStore : NSObject <PreKeyStore>

@property (nonatomic, readonly) SDSKeyValueStore *keyStore;

- (NSArray<PreKeyRecord *> *)generatePreKeyRecords;
- (void)storePreKeyRecords:(NSArray<PreKeyRecord *> *)preKeyRecords NS_SWIFT_NAME(storePreKeyRecords(_:));

#if TESTABLE_BUILD
- (void)removeAll:(SDSAnyWriteTransaction *)transaction;
#endif

@end

NS_ASSUME_NONNULL_END
