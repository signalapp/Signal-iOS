//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class OWSStorage;
@class YapDatabaseReadTransaction;

@interface OWSFailedAttachmentDownloadsJob : NSObject

- (void)run;

+ (NSArray<NSString *> *)unfailedAttachmentPointerIdsWithTransaction:(YapDatabaseReadTransaction *)transaction;

+ (NSString *)databaseExtensionName;
+ (void)asyncRegisterDatabaseExtensionsWithPrimaryStorage:(OWSStorage *)storage;

@end

NS_ASSUME_NONNULL_END
