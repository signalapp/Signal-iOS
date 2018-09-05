//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSPrimaryStorage.h"
#import <AxolotlKit/PreKeyStore.h>

@interface OWSPrimaryStorage (PreKeyStore) <PreKeyStore>

- (NSArray<PreKeyRecord *> *)generatePreKeyRecords;
- (void)storePreKeyRecords:(NSArray *)preKeyRecords;

@end
