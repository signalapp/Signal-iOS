//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "TSDatabaseView.h"
#import "OWSReadTracking.h"
#import "TSAttachment.h"
#import "TSAttachmentPointer.h"
#import "TSIncomingMessage.h"
#import "TSOutgoingMessage.h"
#import "TSThread.h"
#import <YapDatabase/YapDatabaseAutoView.h>
#import <YapDatabase/YapDatabaseCrossProcessNotification.h>
#import <YapDatabase/YapDatabaseViewTypes.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const TSInboxGroup = @"TSInboxGroup";
NSString *const TSArchiveGroup = @"TSArchiveGroup";

NSString *const TSUnreadIncomingMessagesGroup = @"TSUnreadIncomingMessagesGroup";
NSString *const TSSecondaryDevicesGroup = @"TSSecondaryDevicesGroup";

// YAPDB BUG: when changing from non-persistent to persistent view, we had to rename TSThreadDatabaseViewExtensionName
// -> TSThreadDatabaseViewExtensionName2 to work around https://github.com/yapstudios/YapDatabase/issues/324
NSString *const TSThreadDatabaseViewExtensionName = @"TSThreadDatabaseViewExtensionName2";

// We sort interactions by a monotonically increasing counter.
//
// Previously we sorted the interactions database by local timestamp, which was problematic if the local clock changed.
// We need to maintain the legacy extension for purposes of migration.
//
// The "Legacy" sorting extension name constant has the same value as always, so that it won't need to be rebuilt, while
// the "Modern" sorting extension name constant has the same symbol name that we've always used for sorting
// interactions, so that the callsites won't need to change.
NSString *const TSMessageDatabaseViewExtensionName = @"TSMessageDatabaseViewExtensionName_Monotonic";
NSString *const TSMessageDatabaseViewExtensionName_Legacy = @"TSMessageDatabaseViewExtensionName";

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
    YapDatabaseView *existingView = [storage registeredExtension:viewName];
    if (existingView) {
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
                                      version:@"2"
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
                                      version:@"2"
                                      storage:storage];
}

+ (void)asyncRegisterLegacyThreadInteractionsDatabaseView:(OWSStorage *)storage
{
    YapDatabaseView *existingView = [storage registeredExtension:TSMessageDatabaseViewExtensionName_Legacy];
    if (existingView) {
        return;
    }

    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *(
        YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object) {
        if (![object isKindOfClass:[TSInteraction class]]) {
            return nil;
        }
        TSInteraction *interaction = (TSInteraction *)object;

        return interaction.uniqueThreadId;
    }];

    YapDatabaseViewSorting *viewSorting =
        [YapDatabaseViewSorting withObjectBlock:^NSComparisonResult(YapDatabaseReadTransaction *transaction,
            NSString *group,
            NSString *collection1,
            NSString *key1,
            id object1,
            NSString *collection2,
            NSString *key2,
            id object2) {
            if (![object1 isKindOfClass:[TSInteraction class]]) {
                return NSOrderedSame;
            }
            if (![object2 isKindOfClass:[TSInteraction class]]) {
                return NSOrderedSame;
            }
            TSInteraction *interaction1 = (TSInteraction *)object1;
            TSInteraction *interaction2 = (TSInteraction *)object2;

            // Legit usage of timestampForLegacySorting since we're registering the
            // legacy extension
            uint64_t timestamp1 = interaction1.timestampForLegacySorting;
            uint64_t timestamp2 = interaction2.timestampForLegacySorting;

            if (timestamp1 > timestamp2) {
                return NSOrderedDescending;
            } else if (timestamp1 < timestamp2) {
                return NSOrderedAscending;
            } else {
                return NSOrderedSame;
            }
        }];

    YapDatabaseViewOptions *options = [YapDatabaseViewOptions new];
    options.isPersistent = YES;
    options.allowedCollections =
        [[YapWhitelistBlacklist alloc] initWithWhitelist:[NSSet setWithObject:[TSInteraction collection]]];

    YapDatabaseView *view =
        [[YapDatabaseAutoView alloc] initWithGrouping:viewGrouping sorting:viewSorting versionTag:@"1" options:options];

    [storage asyncRegisterExtension:view withName:TSMessageDatabaseViewExtensionName_Legacy];
}

+ (void)asyncRegisterThreadInteractionsDatabaseView:(OWSStorage *)storage
{
    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *(
        YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object) {
        if (![object isKindOfClass:[TSInteraction class]]) {
            return nil;
        }
        TSInteraction *interaction = (TSInteraction *)object;

        return interaction.uniqueThreadId;
    }];

    [self registerMessageDatabaseViewWithName:TSMessageDatabaseViewExtensionName
                                 viewGrouping:viewGrouping
                                      version:@"2"
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
                                      version:@"3"
                                      storage:storage];
}

+ (void)asyncRegisterThreadDatabaseView:(OWSStorage *)storage
{
    YapDatabaseView *threadView = [storage registeredExtension:TSThreadDatabaseViewExtensionName];
    if (threadView) {
        return;
    }

    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *(
        YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object) {
        if (![object isKindOfClass:[TSThread class]]) {
            return nil;
        }
        TSThread *thread = (TSThread *)object;

        if (thread.shouldBeVisible) {
            // Do nothing; we never hide threads that have ever had a message.
        } else {
            YapDatabaseViewTransaction *viewTransaction = [transaction ext:TSMessageDatabaseViewExtensionName];
            NSUInteger threadMessageCount = [viewTransaction numberOfItemsInGroup:thread.uniqueId];
            if (threadMessageCount < 1) {
                return nil;
            }
        }

        return TSInboxGroup;
    }];

    YapDatabaseViewSorting *viewSorting = [self threadSorting];

    YapDatabaseViewOptions *options = [[YapDatabaseViewOptions alloc] init];
    options.isPersistent = YES;
    options.allowedCollections =
        [[YapWhitelistBlacklist alloc] initWithWhitelist:[NSSet setWithObject:[TSThread collection]]];

    YapDatabaseView *databaseView =
        [[YapDatabaseAutoView alloc] initWithGrouping:viewGrouping sorting:viewSorting versionTag:@"4" options:options];

    [storage asyncRegisterExtension:databaseView withName:TSThreadDatabaseViewExtensionName];
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
            return NSOrderedSame;
        }
        if (![object2 isKindOfClass:[TSThread class]]) {
            return NSOrderedSame;
        }
        TSThread *thread1 = (TSThread *)object1;
        TSThread *thread2 = (TSThread *)object2;
        if ([group isEqualToString:TSArchiveGroup] || [group isEqualToString:TSInboxGroup]) {
            
            TSInteraction *_Nullable lastInteractionForInbox1 =
                [thread1 lastInteractionForInboxWithTransaction:transaction];
            NSDate *lastInteractionForInboxDate1 = lastInteractionForInbox1 ? lastInteractionForInbox1.receivedAtDate : thread1.creationDate;

            TSInteraction *_Nullable lastInteractionForInbox2 =
                [thread2 lastInteractionForInboxWithTransaction:transaction];
            NSDate *lastInteractionForInboxDate2 = lastInteractionForInbox2 ? lastInteractionForInbox2.receivedAtDate : thread2.creationDate;


            NSDate *date1 = thread1.lastInteractionDate ?: lastInteractionForInboxDate1 ?: thread1.creationDate;
            NSDate *date2 = thread2.lastInteractionDate ?: lastInteractionForInboxDate2 ?: thread2.creationDate;
            return [date1 compare:date2];
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
            return NSOrderedSame;
        }
        if (![object2 isKindOfClass:[TSInteraction class]]) {
            return NSOrderedSame;
        }
        TSInteraction *message1 = (TSInteraction *)object1;
        TSInteraction *message2 = (TSInteraction *)object2;

        return [message1 compareForSorting:message2];
    }];
}

+ (void)asyncRegisterLazyRestoreAttachmentsDatabaseView:(OWSStorage *)storage
{
    YapDatabaseViewGrouping *viewGrouping = [YapDatabaseViewGrouping withObjectBlock:^NSString *_Nullable(
        YapDatabaseReadTransaction *transaction, NSString *collection, NSString *key, id object) {
        if (![object isKindOfClass:[TSAttachment class]]) {
            return nil;
        }
        if (![object isKindOfClass:[TSAttachmentPointer class]]) {
            return nil;
        }
        TSAttachmentPointer *attachmentPointer = (TSAttachmentPointer *)object;
        if (attachmentPointer.lazyRestoreFragment) {
            return TSLazyRestoreAttachmentsGroup;
        } else {
            return nil;
        }
    }];

    YapDatabaseViewSorting *viewSorting =
        [YapDatabaseViewSorting withObjectBlock:^NSComparisonResult(YapDatabaseReadTransaction *transaction,
            NSString *group,
            NSString *collection1,
            NSString *key1,
            id object1,
            NSString *collection2,
            NSString *key2,
            id object2) {
            if (![object1 isKindOfClass:[TSAttachmentPointer class]]) {
                return NSOrderedSame;
            }
            if (![object2 isKindOfClass:[TSAttachmentPointer class]]) {
                return NSOrderedSame;
            }

            // Specific ordering doesn't matter; we just need a stable ordering.
            TSAttachmentPointer *attachmentPointer1 = (TSAttachmentPointer *)object1;
            TSAttachmentPointer *attachmentPointer2 = (TSAttachmentPointer *)object2;
            return [attachmentPointer1.uniqueId compare:attachmentPointer2.uniqueId];
        }];

    YapDatabaseViewOptions *options = [YapDatabaseViewOptions new];
    options.isPersistent = YES;
    options.allowedCollections =
        [[YapWhitelistBlacklist alloc] initWithWhitelist:[NSSet setWithObject:[TSAttachment collection]]];
    YapDatabaseView *view =
        [[YapDatabaseAutoView alloc] initWithGrouping:viewGrouping sorting:viewSorting versionTag:@"4" options:options];
    [storage asyncRegisterExtension:view withName:TSLazyRestoreAttachmentsDatabaseViewExtensionName];
}

+ (id)unseenDatabaseViewExtension:(YapDatabaseReadTransaction *)transaction
{
    id _Nullable result = [transaction ext:TSUnseenDatabaseViewExtensionName];

    // TODO: I believe we can now safely remove this?
    if (!result) {
        result = [transaction ext:TSUnreadDatabaseViewExtensionName];
    }

    return result;
}

// MJK TODO - dynamic interactions
+ (id)threadOutgoingMessageDatabaseView:(YapDatabaseReadTransaction *)transaction
{
    id result = [transaction ext:TSThreadOutgoingMessageDatabaseViewExtensionName];

    return result;
}

+ (id)threadSpecialMessagesDatabaseView:(YapDatabaseReadTransaction *)transaction
{
    id result = [transaction ext:TSThreadSpecialMessagesDatabaseViewExtensionName];

    return result;
}

@end

NS_ASSUME_NONNULL_END
