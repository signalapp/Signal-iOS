//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <AxolotlKit/PreKeyStore.h>
#import "TSStorageManager.h"

@interface TSStorageManager (PreKeyStore) <PreKeyStore>

- (NSArray *)generatePreKeyRecords;
- (PreKeyRecord *)getOrGenerateLastResortKey;
- (void)storePreKeyRecords:(NSArray *)preKeyRecords;

@end
