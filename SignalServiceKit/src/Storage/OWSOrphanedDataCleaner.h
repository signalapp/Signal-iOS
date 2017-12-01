//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

// Notes:
//
// * On disk, we only bother cleaning up files, not directories.
// * For code simplicity, we don't guarantee that everything is
//   cleaned up in a single pass. If an interaction is cleaned up,
//   it's attachments might not be cleaned up until the next pass.
//   If an attachment is cleaned up, it's file on disk might not
//   be cleaned up until the next pass.
@interface OWSOrphanedDataCleaner : NSObject

- (instancetype)init NS_UNAVAILABLE;

+ (void)auditAsync;

// completion, if present, will be invoked on the main thread.
+ (void)auditAndCleanupAsync:(void (^_Nullable)(void))completion;

+ (NSSet<NSString *> *)filePathsInAttachmentsFolder;

+ (long long)fileSizeOfFilePaths:(NSArray<NSString *> *)filePaths;

@end

NS_ASSUME_NONNULL_END
