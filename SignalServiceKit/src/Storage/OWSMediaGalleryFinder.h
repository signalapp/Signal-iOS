//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSStorage;
@class TSAttachment;
@class TSThread;
@class YapDatabaseReadTransaction;

@interface OWSMediaGalleryFinder : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread NS_DESIGNATED_INITIALIZER;

// How many media items a thread has
- (NSUInteger)mediaCountWithTransaction:(YapDatabaseReadTransaction *)transaction NS_SWIFT_NAME(mediaCount(transaction:));

// The ordinal position of an attachment within a thread's media gallery
- (NSUInteger)mediaIndexForAttachment:(TSAttachment *)attachment
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

#pragma mark - Extension registration

+ (NSString *)databaseExtensionName;
+ (void)asyncRegisterDatabaseExtensionsWithPrimaryStorage:(OWSStorage *)storage;

@end

NS_ASSUME_NONNULL_END
