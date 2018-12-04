//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "TSYapDatabaseObject.h"

NS_ASSUME_NONNULL_BEGIN

// We store metadata for known backup fragments (i.e.  CloudKit record) in
// the database.  We might learn about them from:
//
// * Past backup exports.
// * An import downloading and parsing the manifest of the last complete backup.
//
// Storing this data in the database provides continuity.
//
// * Backup exports can reuse fragments from previous Backup exports even if they
//   don't complete (i.e. backup export resume).
// * Backup exports can reuse fragments from the backup import, if any.
@interface OWSBackupFragment : TSYapDatabaseObject

@property (nonatomic) NSString *recordName;

@property (nonatomic) NSData *encryptionKey;

// This property is only set for certain types of manifest item,
// namely attachments where we need to know where the attachment's
// file should reside relative to the attachments folder.
@property (nonatomic, nullable) NSString *relativeFilePath;

// This property is only set for attachments.
@property (nonatomic, nullable) NSString *attachmentId;

// This property is only set if the manifest item is downloaded.
@property (nonatomic, nullable) NSString *downloadFilePath;

// This property is only set if the manifest item is compressed.
@property (nonatomic, nullable) NSNumber *uncompressedDataLength;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
