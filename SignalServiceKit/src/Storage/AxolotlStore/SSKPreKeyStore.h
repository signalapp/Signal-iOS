//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import <AxolotlKit/PreKeyStore.h>

NS_ASSUME_NONNULL_BEGIN

@interface SSKPreKeyStore : NSObject <PreKeyStore>

- (NSArray<PreKeyRecord *> *)generatePreKeyRecords;
- (void)storePreKeyRecords:(NSArray<PreKeyRecord *> *)preKeyRecords NS_SWIFT_NAME(storePreKeyRecords(_:));

@end

NS_ASSUME_NONNULL_END
