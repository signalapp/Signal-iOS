//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <SignalUtilitiesKit/OWSPrimaryStorage.h>
#import <SessionProtocolKit/PreKeyStore.h>

NS_ASSUME_NONNULL_BEGIN

@interface OWSPrimaryStorage (PreKeyStore) <PreKeyStore>

- (NSArray<PreKeyRecord *> *)generatePreKeyRecords;
- (NSArray<PreKeyRecord *> *)generatePreKeyRecords:(int)batchSize;
- (void)storePreKeyRecords:(NSArray<PreKeyRecord *> *)preKeyRecords NS_SWIFT_NAME(storePreKeyRecords(_:));

@end

NS_ASSUME_NONNULL_END
