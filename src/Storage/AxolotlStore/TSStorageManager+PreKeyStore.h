//
//  TSStorageManager+PreKeyStore.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 06/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <AxolotlKit/PreKeyStore.h>
#import "TSStorageManager.h"

@interface TSStorageManager (PreKeyStore) <PreKeyStore>

- (NSArray *)generatePreKeyRecords;
- (PreKeyRecord *)getOrGenerateLastResortKey;
- (void)storePreKeyRecords:(NSArray *)preKeyRecords;

@end
