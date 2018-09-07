//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSDatabaseView.h"
#import "OWSDevice.h"
#import "OWSReadTracking.h"
#import "TSAttachment.h"
#import "TSAttachmentStream.h"
#import "TSIncomingMessage.h"
#import "TSInvalidIdentityKeyErrorMessage.h"
#import "TSOutgoingMessage.h"
#import "TSThread.h"
#import <YapDatabase/YapDatabaseAutoView.h>
#import <YapDatabase/YapDatabaseCrossProcessNotification.h>
#import <YapDatabase/YapDatabaseViewTypes.h>

NSString *const TSInboxGroup = @"TSInboxGroup";
NSString *const TSArchiveGroup = @"TSArchiveGroup";

NSString *const TSUnreadIncomingMessagesGroup = @"TSUnreadIncomingMessagesGroup";
NSString *const TSSecondaryDevicesGroup = @"TSSecondaryDevicesGroup";

// YAPDB BUG: when changing from non-persistent to persistent view, we had to rename TSThreadDatabaseViewExtensionName
// -> TSThreadDatabaseViewExtensionName2 to work around https://github.com/yapstudios/YapDatabase/issues/324
NSString *const TSThreadDatabaseViewExtensionName = @"TSThreadDatabaseViewExtensionName2";
NSString *const TSMessageDatabaseViewExtensionName = @"TSMessageDatabaseViewExtensionName";
NSString *const TSThreadOutgoingMessageDatabaseViewExtensionName = @"TSThreadOutgoingMessageDatabaseViewExtensionName";
NSString *const TSUnreadDatabaseViewExtensionName = @"TSUnreadDatabaseViewExtensionName";
NSString *const TSUnseenDatabaseViewExtensionName = @"TSUnseenDatabaseViewExtensionName";
NSString *const TSThreadSpecialMessagesDatabaseViewExtensionName = @"TSThreadSpecialMessagesDatabaseViewExtensionName";
NSString *const TSSecondaryDevicesDatabaseViewExtensionName = @"TSSecondaryDevicesDatabaseViewExtensionName";
NSString *const TSLazyRestoreAttachmentsDatabaseViewExtensionName
    = @"TSLazyRestoreAttachmentsDatabaseViewExtensionName";
NSString *const TSLazyRestoreAttachmentsGroup = @"TSLazyRestoreAttachmentsGroup";

@interface OWSStorage (TSDatabaseView)

- (BOOL)registerExtension:(YapDatabaseExtension *)extension withName:(NSString *)extensionName;

@end

#pragma mark -

@implementation TSDatabaseView

+ (void)registerCrossProcessNotifier:(OWSStorage *)storage
{
    OWSAssertDebug(storage);

    // I don't think the identifier and name of this extension matter for our purposes,
    // so long as they don't conflict with any other extension names.
    YapDatabaseExtension *extension =
        [[YapDatabaseCrossProcessNotification alloc] initWithIdentifier:@"SignalCrossProcessNotifier"];
    [storage registerExtension:extension withName:@"SignalCrossProcessNotifier"];
}

+ (void)registerMessageDatabaseViewWithName:(NSString *)viewName
                               viewGrouping:(YapDatabaseViewGrouping *)viewGrouping
                                    version:(NSString *)version
                                    storage:(OWSStorage *)storage
{
    OWSAssertIsOnMainThread();
    OWSAssertDebug(viewName.length > 0);
    OWSAssertDebug((viewGrouping));
    OWSAssertDebug(storage);

    YapDatabaseView *existingView = [storage registeredExtension:viewName];
    if (existingView) {
        OWSFailDebug(@"Registered database view twice: %@", viewName);
        return;
    }

    YapDatabaseViewSorting *viewSorting = [self messagesSorting];

    YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
    options.isPersistent = YES;
    options.allowedCollections =
        [[YapWhitelistBlacklist alloc] initWithWhitelist:[NSSet setWithObject:[TSInteraction collection]]];

    YapDatabaseView *view = [[YapDatabaseAutoView alloc] initWithGrouping:viewGrouping
                                                                  sorting:viewSorting
                                                               versionTag:version
                                                                  options:options];
    [storage asyncRegisterExtension:view withName:viewName];
}

+ (void)asyncRegisterUnreadDatabaseView:(OWSStorage *)storage
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

    [self registerMessageDatabaseViewWithName:TSUnreadDatabaseViewExtensionName
                                 viewGrouping:viewGrouping
                                      version:@"1"
                                      storage:storage];
}

+ (void)asyncRegisterUnseenDatabaseView:(OWSStorage *)storage
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

    [self registerMessageDatabaseViewWithName:TSUnseenDatabaseViewExtensionName
                                 viewGrouping:viewGrouping
                                      version:@"1"
                                      storage:storage];
}

+ (void)asyncRegisterThreadSpecialMessagesDatabaseView:(OWSStorage *)storage
{
    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *(
        YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object) {
        if (![object isKindOfClass:[TSInteraction class]]) {
            OWSFailDebug(@"Unexpected entity %@ in collection: %@", [object class], collection);
            return nil;
        }
        TSInteraction *interaction = (TSInteraction *)object;
        if ([interaction isDynamicInteraction]) {
            return interaction.uniqueThreadId;
        } else if ([object isKindOfClass:[TSInvalidIdentityKeyErrorMessage class]]) {
            return interaction.uniqueThreadId;
        } else if ([object isKindOfClass:[TSErrorMessage class]]) {
            TSErrorMessage *errorMessage = (TSErrorMessage *)object;
            if (errorMessage.errorType == TSErrorMessageNonBlockingIdentityChange) {
                return errorMessage.uniqueThreadId;
            }
        }
        return nil;
    }];

    [self registerMessageDatabaseViewWithName:TSThreadSpecialMessagesDatabaseViewExtensionName
                                 viewGrouping:viewGrouping
                                      version:@"1"
                                      storage:storage];
}

+ (void)asyncRegisterThreadInteractionsDatabaseView:(OWSStorage *)storage
{
    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *(
        YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object) {
        if (![object isKindOfClass:[TSInteraction class]]) {
            OWSFailDebug(@"Unexpected entity %@ in collection: %@", [object class], collection);
            return nil;
        }
        TSInteraction *interaction = (TSInteraction *)object;

        return interaction.uniqueThreadId;
    }];

    [self registerMessageDatabaseViewWithName:TSMessageDatabaseViewExtensionName
                                 viewGrouping:viewGrouping
                                      version:@"1"
                                      storage:storage];
}

+ (void)asyncRegisterThreadOutgoingMessagesDatabaseView:(OWSStorage *)storage
{
    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *(
        YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object) {
        if ([object isKindOfClass:[TSOutgoingMessage class]]) {
            return ((TSOutgoingMessage *)object).uniqueThreadId;
        }
        return nil;
    }];

    [self registerMessageDatabaseViewWithName:TSThreadOutgoingMessageDatabaseViewExtensionName
                                 viewGrouping:viewGrouping
                                      version:@"2"
                                      storage:storage];
}

+ (void)asyncRegisterThreadDatabaseView:(OWSStorage *)storage
{
    YapDatabaseView *threadView = [storage registeredExtension:TSThreadDatabaseViewExtensionName];
    if (threadView) {
        OWSFailDebug(@"Registered database view twice: %@", TSThreadDatabaseViewExtensionName);
        return;
    }

    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *(
        YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object) {
        if (![object isKindOfClass:[TSThread class]]) {
            OWSFailDebug(@"Unexpected entity %@ in collection: %@", [object class], collection);
            return nil;
        }
        TSThread *thread = (TSThread *)object;

        if (thread.isGroupThread) {
            // Do nothing; we never hide group threads.
        } else if (thread.hasEverHadMessage) {
            // Do nothing; we never hide threads that have ever had a message.
        } else {
            YapDatabaseViewTransaction *viewTransaction = [transaction ext:TSMessageDatabaseViewExtensionName];
            OWSAssertDebug(viewTransaction);
            NSUInteger threadMessageCount = [viewTransaction numberOfItemsInGroup:thread.uniqueId];
            if (threadMessageCount < 1) {
                return nil;
            }
        }

        if (thread.archivalDate) {
            return ([self threadShouldBeInInbox:thread]) ? TSInboxGroup : TSArchiveGroup;
        } else if (thread.archivalDate) {
            return TSArchiveGroup;
        } else {
            return TSInboxGroup;
        }
    }];

    YapDatabaseViewSorting *viewSorting = [self threadSorting];

    YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
    options.isPersistent = YES;
    options.allowedCollections =
        [[YapWhitelistBlacklist alloc] initWithWhitelist:[NSSet setWithObject:[TSThread collection]]];

    YapDatabaseView *databaseView =
        [[YapDatabaseAutoView alloc] initWithGrouping:viewGrouping sorting:viewSorting versionTag:@"3" options:options];

    [storage asyncRegisterExtension:databaseView withName:TSThreadDatabaseViewExtensionName];
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
        if (![object1 isKindOfClass:[TSThread class]]) {
            OWSFailDebug(@"Unexpected entity %@ in collection: %@", [object1 class], collection1);
            return NSOrderedSame;
        }
        if (![object2 isKindOfClass:[TSThread class]]) {
            OWSFailDebug(@"Unexpected entity %@ in collection: %@", [object2 class], collection2);
            return NSOrderedSame;
        }
        TSThread *thread1 = (TSThread *)object1;
        TSThread *thread2 = (TSThread *)object2;
        if ([group isEqualToString:TSArchiveGroup] || [group isEqualToString:TSInboxGroup]) {
            return [thread1.lastMessageDate compare:thread2.lastMessageDate];
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
        if (![object1 isKindOfClass:[TSInteraction class]]) {
            OWSFailDebug(@"Unexpected entity %@ in collection: %@", [object1 class], collection1);
            return NSOrderedSame;
        }
        if (![object2 isKindOfClass:[TSInteraction class]]) {
            OWSFailDebug(@"Unexpected entity %@ in collection: %@", [object2 class], collection2);
            return NSOrderedSame;
        }
        TSInteraction *message1 = (TSInteraction *)object1;
        TSInteraction *message2 = (TSInteraction *)object2;

        return [message1 compareForSorting:message2];
    }];
}

+ (void)asyncRegisterSecondaryDevicesDatabaseView:(OWSStorage *)storage
{
    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *_Nullable(
        YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object) {
        if (![object isKindOfClass:[OWSDevice class]]) {
            OWSFailDebug(@"Unexpected entity %@ in collection: %@", [object class], collection);
            return nil;
        }
        OWSDevice *device = (OWSDevice *)object;
        if (![device isPrimaryDevice]) {
            return TSSecondaryDevicesGroup;
        }
        return nil;
    }];

    YapDatabaseViewSorting *viewSorting = [YapDatabaseViewSorting withObjectBlock:^NSComparisonResult(
        YapDatabaseReadTransaction *transaction,
        NSString *group,
        NSString *collection1,
        NSString *key1,
        id object1,
        NSString *collection2,
        NSString *key2,
        id object2) {
        if (![object1 isKindOfClass:[OWSDevice class]]) {
            OWSFailDebug(@"Unexpected entity %@ in collection: %@", [object1 class], collection1);
            return NSOrderedSame;
        }
        if (![object2 isKindOfClass:[OWSDevice class]]) {
            OWSFailDebug(@"Unexpected entity %@ in collection: %@", [object2 class], collection2);
            return NSOrderedSame;
        }
        OWSDevice *device1 = (OWSDevice *)object1;
        OWSDevice *device2 = (OWSDevice *)object2;

        return [device2.createdAt compare:device1.createdAt];
    }];

    YapDatabaseViewOptions *options = [YapDatabaseViewOptions new];
    options.isPersistent = YES;

    NSSet *deviceCollection = [NSSet setWithObject:[OWSDevice collection]];
    options.allowedCollections = [[YapWhitelistBlacklist alloc] initWithWhitelist:deviceCollection];

    YapDatabaseView *view =
        [[YapDatabaseAutoView alloc] initWithGrouping:viewGrouping sorting:viewSorting versionTag:@"3" options:options];

    [storage asyncRegisterExtension:view withName:TSSecondaryDevicesDatabaseViewExtensionName];
}

+ (void)asyncRegisterLazyRestoreAttachmentsDatabaseView:(OWSStorage *)storage
{
    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *_Nullable(
        YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object) {
        if (![object isKindOfClass:[TSAttachment class]]) {
            OWSFailDebug(@"Unexpected entity %@ in collection: %@", [object class], collection);
            return nil;
        }
        if (![object isKindOfClass:[TSAttachmentStream class]]) {
            return nil;
        }
        TSAttachmentStream *attachmentStream = (TSAttachmentStream *)object;
        if (attachmentStream.lazyRestoreFragment) {
            return TSLazyRestoreAttachmentsGroup;
        } else {
            return nil;
        }
    }];

    YapDatabaseViewSorting *viewSorting = [YapDatabaseViewSorting withObjectBlock:^NSComparisonResult(
        YapDatabaseReadTransaction *transaction,
        NSString *group,
        NSString *collection1,
        NSString *key1,
        id object1,
        NSString *collection2,
        NSString *key2,
        id object2) {
        if (![object1 isKindOfClass:[TSAttachmentStream class]]) {
            OWSFailDebug(@"Unexpected entity %@ in collection: %@", [object1 class], collection1);
            return NSOrderedSame;
        }
        if (![object2 isKindOfClass:[TSAttachmentStream class]]) {
            OWSFailDebug(@"Unexpected entity %@ in collection: %@", [object2 class], collection2);
            return NSOrderedSame;
        }

        // Specific ordering doesn't matter; we just need a stable ordering.
        TSAttachmentStream *attachmentStream1 = (TSAttachmentStream *)object1;
        TSAttachmentStream *attachmentStream2 = (TSAttachmentStream *)object2;
        return [attachmentStream2.creationTimestamp compare:attachmentStream1.creationTimestamp];
    }];

    YapDatabaseViewOptions *options = [YapDatabaseViewOptions new];
    options.isPersistent = YES;
    options.allowedCollections =
        [[YapWhitelistBlacklist alloc] initWithWhitelist:[NSSet setWithObject:[TSAttachment collection]]];
    YapDatabaseView *view =
        [[YapDatabaseAutoView alloc] initWithGrouping:viewGrouping sorting:viewSorting versionTag:@"3" options:options];
    [storage asyncRegisterExtension:view withName:TSLazyRestoreAttachmentsDatabaseViewExtensionName];
}

+ (id)unseenDatabaseViewExtension:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    id result = [transaction ext:TSUnseenDatabaseViewExtensionName];

    if (!result) {
        result = [transaction ext:TSUnreadDatabaseViewExtensionName];
        OWSAssertDebug(result);
    }

    return result;
}

+ (id)threadOutgoingMessageDatabaseView:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    id result = [transaction ext:TSThreadOutgoingMessageDatabaseViewExtensionName];
    OWSAssertDebug(result);

    return result;
}

+ (id)threadSpecialMessagesDatabaseView:(YapDatabaseReadTransaction *)transaction
{
    OWSAssertDebug(transaction);

    id result = [transaction ext:TSThreadSpecialMessagesDatabaseViewExtensionName];
    OWSAssertDebug(result);

    return result;
}

@end
