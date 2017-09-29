//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <AxolotlKit/SessionStore.h>
#import "TSStorageManager.h"

@interface TSStorageManager (SessionStore) <SessionStore>

- (void)archiveAllSessionsForContact:(NSString *)contactIdentifier;

#pragma mark - debug

- (void)resetSessionStore;
- (void)printAllSessions;

@end
