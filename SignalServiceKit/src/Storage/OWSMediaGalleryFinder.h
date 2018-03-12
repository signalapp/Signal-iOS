//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSStorage;
@class TSMessage;
@class TSThread;
@class YapDatabaseReadTransaction;

@interface OWSMediaGalleryFinder : NSObject

// How many media items a thread has
- (NSUInteger)mediaCountForThread:(TSThread *)thread transaction:(YapDatabaseReadTransaction *)transaction NS_SWIFT_NAME(mediaCount(thread:transaction:));

// The ordinal position of a message within a thread's media gallery
- (NSUInteger)mediaIndexForMessage:(TSMessage *)message transaction:(YapDatabaseReadTransaction *)transaction NS_SWIFT_NAME(mediaIndex(message:transaction:));

- (void)enumerateMediaMessagesWithThread:(TSThread *)thread
                             transaction:(YapDatabaseReadTransaction *)transaction
                                   block:(void (^)(TSMessage *))messageBlock;

+ (void)asyncRegisterDatabaseExtensionsWithPrimaryStorage:(OWSStorage *)storage;

@end

NS_ASSUME_NONNULL_END
