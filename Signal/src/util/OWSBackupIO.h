//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSBackupEncryptedItem : NSObject

@property (nonatomic) NSString *filePath;

@property (nonatomic) NSData *encryptionKey;

@end

#pragma mark -

@interface OWSBackupIO : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithJobTempDirPath:(NSString *)jobTempDirPath;

#pragma mark - Encrypt

- (nullable OWSBackupEncryptedItem *)encryptFileAsTempFile:(NSString *)srcFilePath;

- (nullable OWSBackupEncryptedItem *)encryptFileAsTempFile:(NSString *)srcFilePath
                                             encryptionKey:(NSData *)encryptionKey;

- (nullable OWSBackupEncryptedItem *)encryptDataAsTempFile:(NSData *)srcData;

- (nullable OWSBackupEncryptedItem *)encryptDataAsTempFile:(NSData *)srcData encryptionKey:(NSData *)encryptionKey;

#pragma mark - Decrypt

- (BOOL)decryptFileAsFile:(NSString *)srcFilePath
              dstFilePath:(NSString *)dstFilePath
            encryptionKey:(NSData *)encryptionKey;

- (nullable NSData *)decryptFileAsData:(NSString *)srcFilePath encryptionKey:(NSData *)encryptionKey;

- (nullable NSData *)decryptDataAsData:(NSData *)srcData encryptionKey:(NSData *)encryptionKey;

#pragma mark - Compression

- (nullable NSData *)compressData:(NSData *)srcData;

- (nullable NSData *)decompressData:(NSData *)srcData uncompressedDataLength:(NSUInteger)uncompressedDataLength;

@end

NS_ASSUME_NONNULL_END
