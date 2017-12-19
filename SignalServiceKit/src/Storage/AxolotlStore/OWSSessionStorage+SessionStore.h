//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSSessionStorage.h"
#import <AxolotlKit/SessionStore.h>

// TODO: Dispatch to OWSDispatch.sessionStoreQueue internally, if possible.
@interface OWSSessionStorage (SessionStore) <SessionStore>

- (void)archiveAllSessionsForContact:(NSString *)contactIdentifier;

- (void)migrateFromStorageIfNecessary:(OWSStorage *)storage;

#pragma mark - debug

- (void)resetSessionStore;

- (void)printAllSessions;

@end
