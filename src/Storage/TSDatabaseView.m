//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "TSDatabaseView.h"
#import "OWSDevice.h"
#import "OWSReadTracking.h"
#import "TSIncomingMessage.h"
#import "TSInvalidIdentityKeyErrorMessage.h"
#import "TSOutgoingMessage.h"
#import "TSStorageManager.h"
#import "TSThread.h"
#import <YapDatabase/YapDatabaseView.h>

NSString *TSInboxGroup   = @"TSInboxGroup";
NSString *TSArchiveGroup = @"TSArchiveGroup";

NSString *TSUnreadIncomingMessagesGroup = @"TSUnreadIncomingMessagesGroup";
NSString *TSSecondaryDevicesGroup = @"TSSecondaryDevicesGroup";

NSString *TSThreadDatabaseViewExtensionName  = @"TSThreadDatabaseViewExtensionName";
NSString *TSMessageDatabaseViewExtensionName = @"TSMessageDatabaseViewExtensionName";
NSString *TSThreadIncomingMessageDatabaseViewExtensionName = @"TSThreadOutgoingMessageDatabaseViewExtensionName";
NSString *TSThreadOutgoingMessageDatabaseViewExtensionName = @"TSThreadOutgoingMessageDatabaseViewExtensionName";
NSString *TSUnreadDatabaseViewExtensionName  = @"TSUnreadDatabaseViewExtensionName";
NSString *TSUnseenDatabaseViewExtensionName = @"TSUnseenDatabaseViewExtensionName";
NSString *TSDynamicMessagesDatabaseViewExtensionName = @"TSDynamicMessagesDatabaseViewExtensionName";
NSString *TSSafetyNumberChangeDatabaseViewExtensionName = @"TSSafetyNumberChangeDatabaseViewExtensionName";
NSString *TSSecondaryDevicesDatabaseViewExtensionName = @"TSSecondaryDevicesDatabaseViewExtensionName";

@implementation TSDatabaseView

+ (BOOL)registerMessageDatabaseViewWithName:(NSString *)viewName
                               viewGrouping:(YapDatabaseViewGrouping *)viewGrouping
                                    version:(NSString *)version
{
    OWSAssert(viewName.length > 0);
    OWSAssert((viewGrouping));

    YapDatabaseView *existingView = [[TSStorageManager sharedManager].database registeredExtension:viewName];
    if (existingView) {
        return YES;
    }

    YapDatabaseViewSorting *viewSorting = [self messagesSorting];

    YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
    options.isPersistent = YES;
    options.allowedCollections =
        [[YapWhitelistBlacklist alloc] initWithWhitelist:[NSSet setWithObject:[TSInteraction collection]]];

    YapDatabaseView *view =
        [[YapDatabaseView alloc] initWithGrouping:viewGrouping sorting:viewSorting versionTag:version options:options];

    return [[TSStorageManager sharedManager].database registerExtension:view withName:viewName];
}

+ (BOOL)registerUnreadDatabaseView
{
    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *(
        YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object) {
        if ([object conformsToProtocol:@protocol(OWSReadTracking)]) {
            id<OWSReadTracking> possiblyRead = (id<OWSReadTracking>)object;
            if (!possiblyRead.wasRead && possiblyRead.shouldAffectUnreadCounts) {
                return possiblyRead.uniqueThreadId;
            }
        }
        return nil;
    }];

    return [self registerMessageDatabaseViewWithName:TSUnreadDatabaseViewExtensionName
                                        viewGrouping:viewGrouping
                                             version:@"1"];
}

+ (BOOL)registerUnseenDatabaseView
{
    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *(
        YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object) {
        if ([object conformsToProtocol:@protocol(OWSReadTracking)]) {
            id<OWSReadTracking> possiblyRead = (id<OWSReadTracking>)object;
            if (!possiblyRead.wasRead) {
                return possiblyRead.uniqueThreadId;
            }
        }
        return nil;
    }];

    return [self registerMessageDatabaseViewWithName:TSUnseenDatabaseViewExtensionName
                                        viewGrouping:viewGrouping
                                             version:@"1"];
}

+ (BOOL)registerDynamicMessagesDatabaseView
{
    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *(
        YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object) {
        if ([object isKindOfClass:[TSInteraction class]]) {
            TSInteraction *interaction = (TSInteraction *)object;
            if ([interaction isDynamicInteraction]) {
                return interaction.uniqueThreadId;
            }
        } else {
            OWSAssert(0);
        }
        return nil;
    }];

    return [self registerMessageDatabaseViewWithName:TSDynamicMessagesDatabaseViewExtensionName
                                        viewGrouping:viewGrouping
                                             version:@"3"];
}

+ (BOOL)registerSafetyNumberChangeDatabaseView
{
    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *(
        YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object) {
        if ([object isKindOfClass:[TSInvalidIdentityKeyErrorMessage class]]) {
            TSInteraction *interaction = (TSInteraction *)object;
            return interaction.uniqueThreadId;
        } else if ([object isKindOfClass:[TSErrorMessage class]]) {
            TSErrorMessage *errorMessage = (TSErrorMessage *)object;
            if (errorMessage.errorType == TSErrorMessageNonBlockingIdentityChange) {
                return errorMessage.uniqueThreadId;
            }
        }
        return nil;
    }];

    return [self registerMessageDatabaseViewWithName:TSSafetyNumberChangeDatabaseViewExtensionName
                                        viewGrouping:viewGrouping
                                             version:@"2"];
}

+ (BOOL)registerThreadInteractionsDatabaseView
{
    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *(
        YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object) {
        if ([object isKindOfClass:[TSInteraction class]]) {
            return ((TSInteraction *)object).uniqueThreadId;
        }
        return nil;
    }];

    return [self registerMessageDatabaseViewWithName:TSMessageDatabaseViewExtensionName
                                        viewGrouping:viewGrouping
                                             version:@"1"];
}

+ (BOOL)registerThreadIncomingMessagesDatabaseView
{
    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *(
        YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object) {
        if ([object isKindOfClass:[TSIncomingMessage class]]) {
            return ((TSIncomingMessage *)object).uniqueThreadId;
        }
        return nil;
    }];

    return [self registerMessageDatabaseViewWithName:TSThreadIncomingMessageDatabaseViewExtensionName
                                        viewGrouping:viewGrouping
                                             version:@"1"];
}

+ (BOOL)registerThreadOutgoingMessagesDatabaseView
{
    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *(
        YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object) {
        if ([object isKindOfClass:[TSOutgoingMessage class]]) {
            return ((TSOutgoingMessage *)object).uniqueThreadId;
        }
        return nil;
    }];

    return [self registerMessageDatabaseViewWithName:TSThreadOutgoingMessageDatabaseViewExtensionName
                                        viewGrouping:viewGrouping
                                             version:@"1"];
}

+ (BOOL)registerThreadDatabaseView {
    YapDatabaseView *threadView =
        [[TSStorageManager sharedManager].database registeredExtension:TSThreadDatabaseViewExtensionName];
    if (threadView) {
        return YES;
    }

    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping
        withObjectBlock:^NSString *(
            YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object) {
          if ([object isKindOfClass:[TSThread class]]) {
              TSThread *thread = (TSThread *)object;
              if (thread.archivalDate) {
                  return ([self threadShouldBeInInbox:thread]) ? TSInboxGroup : TSArchiveGroup;
              } else if (thread.archivalDate) {
                  return TSArchiveGroup;
              } else {
                  return TSInboxGroup;
              }
          }
          return nil;
        }];

    YapDatabaseViewSorting *viewSorting = [self threadSorting];

    YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
    options.isPersistent            = NO;
    options.allowedCollections =
        [[YapWhitelistBlacklist alloc] initWithWhitelist:[NSSet setWithObject:[TSThread collection]]];

    YapDatabaseView *databaseView =
        [[YapDatabaseView alloc] initWithGrouping:viewGrouping sorting:viewSorting versionTag:@"1" options:options];

    return [[TSStorageManager sharedManager]
                .database registerExtension:databaseView
                                   withName:TSThreadDatabaseViewExtensionName];
}

/**
 *  Determines whether a thread belongs to the archive or inbox
 *
 *  @param thread TSThread
 *
 *  @return Inbox if true, Archive if false
 */

+ (BOOL)threadShouldBeInInbox:(TSThread *)thread {
    NSDate *lastMessageDate = thread.lastMessageDate;
    NSDate *archivalDate    = thread.archivalDate;
    if (lastMessageDate && archivalDate) { // this is what is called
        return ([lastMessageDate timeIntervalSinceDate:archivalDate] > 0)
                   ? YES
                   : NO; // if there hasn't been a new message since the archive date, it's in the archive. an issue is
                         // that empty threads are always given with a lastmessage date of the present on every launch
    } else if (archivalDate) {
        return NO;
    }

    return YES;
}

+ (YapDatabaseViewSorting *)threadSorting {
    return [YapDatabaseViewSorting withObjectBlock:^NSComparisonResult(YapDatabaseReadTransaction *transaction,
                                                                       NSString *group,
                                                                       NSString *collection1,
                                                                       NSString *key1,
                                                                       id object1,
                                                                       NSString *collection2,
                                                                       NSString *key2,
                                                                       id object2) {
      if ([group isEqualToString:TSArchiveGroup] || [group isEqualToString:TSInboxGroup]) {
          if ([object1 isKindOfClass:[TSThread class]] && [object2 isKindOfClass:[TSThread class]]) {
              TSThread *thread1 = (TSThread *)object1;
              TSThread *thread2 = (TSThread *)object2;

              return [thread1.lastMessageDate compare:thread2.lastMessageDate];
          }
      }

      return NSOrderedSame;
    }];
}

+ (YapDatabaseViewSorting *)messagesSorting {
    return [YapDatabaseViewSorting withObjectBlock:^NSComparisonResult(YapDatabaseReadTransaction *transaction,
                                                                       NSString *group,
                                                                       NSString *collection1,
                                                                       NSString *key1,
                                                                       id object1,
                                                                       NSString *collection2,
                                                                       NSString *key2,
                                                                       id object2) {
      if ([object1 isKindOfClass:[TSInteraction class]] && [object2 isKindOfClass:[TSInteraction class]]) {
          TSInteraction *message1 = (TSInteraction *)object1;
          TSInteraction *message2 = (TSInteraction *)object2;

          return [message1 compareForSorting:message2];
      }

      return NSOrderedSame;
    }];
}

+ (void)asyncRegisterSecondaryDevicesDatabaseView
{
    YapDatabaseViewGrouping *viewGrouping =
        [YapDatabaseViewGrouping withObjectBlock:^NSString *_Nullable(YapDatabaseReadTransaction *_Nonnull transaction,
            NSString *_Nonnull collection,
            NSString *_Nonnull key,
            id _Nonnull object) {
            if ([object isKindOfClass:[OWSDevice class]]) {
                OWSDevice *device = (OWSDevice *)object;
                if (![device isPrimaryDevice]) {
                    return TSSecondaryDevicesGroup;
                }
            }
            return nil;
        }];

    YapDatabaseViewSorting *viewSorting =
        [YapDatabaseViewSorting withObjectBlock:^NSComparisonResult(YapDatabaseReadTransaction *_Nonnull transaction,
            NSString *_Nonnull group,
            NSString *_Nonnull collection1,
            NSString *_Nonnull key1,
            id _Nonnull object1,
            NSString *_Nonnull collection2,
            NSString *_Nonnull key2,
            id _Nonnull object2) {

            if ([object1 isKindOfClass:[OWSDevice class]] && [object2 isKindOfClass:[OWSDevice class]]) {
                OWSDevice *device1 = (OWSDevice *)object1;
                OWSDevice *device2 = (OWSDevice *)object2;

                return [device2.createdAt compare:device1.createdAt];
            }

            return NSOrderedSame;
        }];

    YapDatabaseViewOptions *options = [YapDatabaseViewOptions new];
    options.isPersistent = YES;

    NSSet *deviceCollection = [NSSet setWithObject:[OWSDevice collection]];
    options.allowedCollections = [[YapWhitelistBlacklist alloc] initWithWhitelist:deviceCollection];

    YapDatabaseView *view =
        [[YapDatabaseView alloc] initWithGrouping:viewGrouping sorting:viewSorting versionTag:@"3" options:options];

    [[TSStorageManager sharedManager].database
        asyncRegisterExtension:view
                      withName:TSSecondaryDevicesDatabaseViewExtensionName
               completionBlock:^(BOOL ready) {
                   if (ready) {
                       DDLogDebug(@"%@ Successfully set up extension: %@", self.tag, TSSecondaryDevicesGroup);
                   } else {
                       DDLogError(@"%@ Unable to setup extension: %@", self.tag, TSSecondaryDevicesGroup);
                   }
               }];
}

#pragma mark - Logging

+ (NSString *)tag
{
    return [NSString stringWithFormat:@"[%@]", self.class];
}

- (NSString *)tag
{
    return self.class.tag;
}

@end
