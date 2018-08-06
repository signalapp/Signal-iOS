//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSStorage;
@class TSMessage;
@class TSThread;
@class YapDatabaseReadTransaction;

@interface OWSMediaGalleryFinder : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithThread:(TSThread *)thread NS_DESIGNATED_INITIALIZER;

// How many media items a thread has
- (NSUInteger)mediaCountWithTransaction:(YapDatabaseReadTransaction *)transaction NS_SWIFT_NAME(mediaCount(transaction:));

// The ordinal position of a message within a thread's media gallery
- (NSUInteger)mediaIndexForMessage:(TSMessage *)message transaction:(YapDatabaseReadTransaction *)transaction NS_SWIFT_NAME(mediaIndex(message:transaction:));

- (nullable TSMessage *)oldestMediaMessageWithTransaction:(YapDatabaseReadTransaction *)transaction NS_SWIFT_NAME(oldestMediaMessage(transaction:));
- (nullable TSMessage *)mostRecentMediaMessageWithTransaction:(YapDatabaseReadTransaction *)transaction NS_SWIFT_NAME(mostRecentMediaMessage(transaction:));

- (void)enumerateMediaMessagesWithRange:(NSRange)range
                            transaction:(YapDatabaseReadTransaction *)transaction
                                  block:(void (^)(TSMessage *))messageBlock NS_SWIFT_NAME(enumerateMediaMessages(range:transaction:block:));

#pragma mark - Extension registration

+ (NSString *)databaseExtensionName;
+ (void)asyncRegisterDatabaseExtensionsWithPrimaryStorage:(OWSStorage *)storage;

@end

NS_ASSUME_NONNULL_END
