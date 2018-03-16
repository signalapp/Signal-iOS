//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSBackupEncryptedItem : NSObject

@property (nonatomic) NSString *filePath;

@property (nonatomic) NSData *encryptionKey;

@end

#pragma mark -

@interface OWSBackupEncryption : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithJobTempDirPath:(NSString *)jobTempDirPath;

#pragma mark - Encrypt

- (nullable OWSBackupEncryptedItem *)encryptFileAsTempFile:(NSString *)srcFilePath;

- (nullable OWSBackupEncryptedItem *)encryptFileAsTempFile:(NSString *)srcFilePath
                                             encryptionKey:(NSData *)encryptionKey;

- (nullable OWSBackupEncryptedItem *)encryptDataAsTempFile:(NSData *)srcData;

- (nullable OWSBackupEncryptedItem *)encryptDataAsTempFile:(NSData *)srcData encryptionKey:(NSData *)encryptionKey;

#pragma mark - Decrypt

- (nullable NSString *)decryptFileAsTempFile:(NSString *)srcFilePath encryptionKey:(NSData *)encryptionKey;

- (nullable NSData *)decryptDataAsData:(NSData *)srcData encryptionKey:(NSData *)encryptionKey;

@end

NS_ASSUME_NONNULL_END
