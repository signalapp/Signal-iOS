//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "OWSOrphanDataCleaner.h"
#import "OWSProfileManager.h"
#import "Signal-Swift.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalServiceKit/AppReadiness.h>
#import <SignalServiceKit/OWSFileSystem.h>
#import <SignalServiceKit/SignalServiceKit-Swift.h>
#import <SignalServiceKit/TSAttachmentStream.h>
#import <SignalServiceKit/TSInteraction.h>
#import <SignalServiceKit/TSMessage.h>
#import <SignalServiceKit/TSQuotedMessage.h>
#import <SignalServiceKit/TSThread.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSOrphanDataCleaner_LastCleaningVersionKey = @"OWSOrphanDataCleaner_LastCleaningVersionKey";
NSString *const OWSOrphanDataCleaner_LastCleaningDateKey = @"OWSOrphanDataCleaner_LastCleaningDateKey";

@implementation OWSOrphanDataCleaner

+ (void)auditAndCleanup:(BOOL)shouldRemoveOrphans
{
    [self auditAndCleanup:shouldRemoveOrphans completion:^ {}];
}


+ (void)auditAndCleanup:(BOOL)shouldRemoveOrphans completion:(nullable dispatch_block_t)completion
{
    OWSAssertIsOnMainThread();

    if (!AppReadiness.isAppReady) {
        OWSFailDebug(@"can't audit orphan data until app is ready.");
        return;
    }
    if (!CurrentAppContext().isMainApp) {
        OWSFailDebug(@"can't audit orphan data in app extensions.");
        return;
    }

    if (shouldRemoveOrphans) {
        OWSLogInfo(@"Starting orphan data cleanup");
    } else {
        OWSLogInfo(@"Starting orphan data audit");
    }

    // Orphan cleanup has two risks:
    //
    // * As a long-running process that involves access to the
    //   shared data container, it could cause 0xdead10cc.
    // * It could accidentally delete data still in use,
    //   e.g. a profile avatar which has been saved to disk
    //   but whose OWSUserProfile hasn't been saved yet.
    //
    // To prevent 0xdead10cc, the cleaner continually checks
    // whether the app has resigned active.  If so, it aborts.
    // Each phase (search, re-search, processing) retries N times,
    // then gives up until the next app launch.
    //
    // To prevent accidental data deletion, we take the following
    // measures:
    //
    // * Only cleanup data of the following types (which should
    //   include all relevant app data): profile avatar,
    //   attachment, temporary files (including temporary
    //   attachments).
    // * We don't delete any data created more recently than N seconds
    //   _before_ when the app launched.  This prevents any stray data
    //   currently in use by the app from being accidentally cleaned
    //   up.
    const NSInteger kMaxRetries = 3;
    [self findOrphanDataWithRetries:kMaxRetries
        success:^(OWSOrphanData *orphanData) {
            [self processOrphans:orphanData
                remainingRetries:kMaxRetries
                shouldRemoveOrphans:shouldRemoveOrphans
                success:^{
                    OWSLogInfo(@"Completed orphan data cleanup.");

                    DatabaseStorageWrite(self.databaseStorage, ^(SDSAnyWriteTransaction *transaction) {
                        [self.keyValueStore setString:AppVersion.shared.currentAppVersion
                                                  key:OWSOrphanDataCleaner_LastCleaningVersionKey
                                          transaction:transaction];

                        [self.keyValueStore setDate:[NSDate new]
                                                key:OWSOrphanDataCleaner_LastCleaningDateKey
                                        transaction:transaction];
                    });

                    if (completion) {
                        completion();
                    }
                }
                failure:^{
                    OWSLogInfo(@"Aborting orphan data cleanup.");
                    if (completion) {
                        completion();
                    }
                }];
        }
        failure:^{
            OWSLogInfo(@"Aborting orphan data cleanup.");
            if (completion) {
                completion();
            }
        }];
}

@end

NS_ASSUME_NONNULL_END
