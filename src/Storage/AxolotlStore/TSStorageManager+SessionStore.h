//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <AxolotlKit/SessionStore.h>
#import "TSStorageManager.h"

@interface TSStorageManager (SessionStore) <SessionStore>

#pragma mark - debug

- (void)printAllSessions;

@end
