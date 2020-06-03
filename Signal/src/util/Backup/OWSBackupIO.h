//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface OWSBackupEncryptedItem : NSObject

@property (nonatomic) NSString *filePath;

@property (nonatomic) NSData *encryptionKey;

@end

#pragma mark -

@interface OWSBackupIO : NSObject

+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithJobTempDirPath:(NSString *)jobTempDirPath;

- (NSString *)generateTempFilePath;

- (nullable NSString *)createTempFile;

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

// I'm using the (new in iOS 9) compressionlib.  One of its weaknesses is that it
// requires you to pre-allocate output buffers during compression and decompression.
// During decompression this is particularly tricky since there's no way to safely
// predict how large the output will be based on the input.  So, we store the
// uncompressed size for compressed backup items.
- (nullable NSData *)decompressData:(NSData *)srcData uncompressedDataLength:(NSUInteger)uncompressedDataLength;

@end

NS_ASSUME_NONNULL_END
