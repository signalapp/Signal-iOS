//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSStorage;
@class TSAttachment;
@class TSThread;
@class YapDatabaseAutoViewTransaction;
@class YapDatabaseConnection;
@class YapDatabaseReadTransaction;
@class YapDatabaseViewRowChange;

@interface YAPDBMediaGalleryFinder : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread NS_DESIGNATED_INITIALIZER;

// How many media items a thread has
- (NSUInteger)mediaCountWithTransaction:(YapDatabaseReadTransaction *)transaction
    NS_SWIFT_NAME(mediaCount(transaction:));

// The ordinal position of an attachment within a thread's media gallery
- (nullable NSNumber *)mediaIndexForAttachment:(TSAttachment *)attachment
                                   transaction:(YapDatabaseReadTransaction *)transaction
    NS_SWIFT_NAME(mediaIndex(attachment:transaction:));

- (nullable TSAttachment *)oldestMediaAttachmentWithTransaction:(YapDatabaseReadTransaction *)transaction
    NS_SWIFT_NAME(oldestMediaAttachment(transaction:));
- (nullable TSAttachment *)mostRecentMediaAttachmentWithTransaction:(YapDatabaseReadTransaction *)transaction
    NS_SWIFT_NAME(mostRecentMediaAttachment(transaction:));

- (void)enumerateMediaAttachmentsWithRange:(NSRange)range
                               transaction:(YapDatabaseReadTransaction *)transaction
                                     block:(void (^)(TSAttachment *))attachmentBlock
    NS_SWIFT_NAME(enumerateMediaAttachments(range:transaction:block:));

- (BOOL)hasMediaChangesInNotifications:(NSArray<NSNotification *> *)notifications
                          dbConnection:(YapDatabaseConnection *)dbConnection;

#pragma mark - Extension registration

@property (nonatomic, readonly) NSString *mediaGroup;
- (YapDatabaseAutoViewTransaction *)galleryExtensionWithTransaction:(YapDatabaseReadTransaction *)transaction
    NS_SWIFT_NAME(galleryExtension(transaction:));
+ (NSString *)databaseExtensionName;
+ (void)asyncRegisterDatabaseExtensionsWithPrimaryStorage:(OWSStorage *)storage;

@end

NS_ASSUME_NONNULL_END
