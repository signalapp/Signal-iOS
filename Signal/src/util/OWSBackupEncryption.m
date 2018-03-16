//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupEncryption.h"
#import <Curve25519Kit/Randomness.h>
#import <SignalServiceKit/OWSFileSystem.h>

@import Compression;

NS_ASSUME_NONNULL_BEGIN

// TODO:
static const NSUInteger kOWSBackupKeyLength = 32;

@implementation OWSBackupEncryptedItem

@end

#pragma mark -

@interface OWSBackupEncryption ()

@property (nonatomic) NSString *jobTempDirPath;

@end

#pragma mark -

@implementation OWSBackupEncryption

- (instancetype)initWithJobTempDirPath:(NSString *)jobTempDirPath
{
    if (!(self = [super init])) {
        return self;
    }

    self.jobTempDirPath = jobTempDirPath;

    return self;
}

#pragma mark - Encrypt

- (nullable OWSBackupEncryptedItem *)encryptFileAsTempFile:(NSString *)srcFilePath
{
    OWSAssert(srcFilePath.length > 0);

    NSData *encryptionKey = [Randomness generateRandomBytes:(int)kOWSBackupKeyLength];

    return [self encryptFileAsTempFile:srcFilePath encryptionKey:encryptionKey];
}

- (nullable OWSBackupEncryptedItem *)encryptFileAsTempFile:(NSString *)srcFilePath encryptionKey:(NSData *)encryptionKey
{
    OWSAssert(srcFilePath.length > 0);
    OWSAssert(encryptionKey.length > 0);

    // TODO: Encrypt the file without loading it into memory.
    NSData *_Nullable srcData = [NSData dataWithContentsOfFile:srcFilePath];
    if (!srcData) {
        OWSProdLogAndFail(@"%@ could not load file into memory", self.logTag);
        return nil;
    }
    return [self encryptDataAsTempFile:srcData encryptionKey:encryptionKey];
}

- (nullable OWSBackupEncryptedItem *)encryptDataAsTempFile:(NSData *)srcData
{
    OWSAssert(srcData);

    NSData *encryptionKey = [Randomness generateRandomBytes:(int)kOWSBackupKeyLength];

    return [self encryptDataAsTempFile:srcData encryptionKey:encryptionKey];
}

- (nullable OWSBackupEncryptedItem *)encryptDataAsTempFile:(NSData *)srcData encryptionKey:(NSData *)encryptionKey
{
    OWSAssert(srcData);
    OWSAssert(encryptionKey.length > 0);

    // TODO: Encrypt the data using key;

    NSString *dstFilePath = [self.jobTempDirPath stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    NSError *error;
    BOOL success = [srcData writeToFile:dstFilePath options:NSDataWritingAtomic error:&error];
    if (!success || error) {
        OWSProdLogAndFail(@"%@ error writing encrypted data: %@", self.logTag, error);
        return nil;
    }
    [OWSFileSystem protectFileOrFolderAtPath:dstFilePath];
    OWSBackupEncryptedItem *item = [OWSBackupEncryptedItem new];
    item.filePath = dstFilePath;
    item.encryptionKey = encryptionKey;
    return item;
}

#pragma mark - Decrypt

- (BOOL)decryptFileAsFile:(NSString *)srcFilePath
              dstFilePath:(NSString *)dstFilePath
            encryptionKey:(NSData *)encryptionKey
{
    OWSAssert(srcFilePath.length > 0);
    OWSAssert(encryptionKey.length > 0);

    // TODO: Decrypt the file without loading it into memory.
    NSData *data = [self decryptFileAsData:srcFilePath encryptionKey:encryptionKey];

    if (!data) {
        return NO;
    }

    NSError *error;
    BOOL success = [data writeToFile:dstFilePath options:NSDataWritingAtomic error:&error];
    if (!success || error) {
        OWSProdLogAndFail(@"%@ error writing decrypted data: %@", self.logTag, error);
        return NO;
    }
    [OWSFileSystem protectFileOrFolderAtPath:dstFilePath];

    return YES;
}

- (nullable NSData *)decryptFileAsData:(NSString *)srcFilePath encryptionKey:(NSData *)encryptionKey
{
    OWSAssert(srcFilePath.length > 0);
    OWSAssert(encryptionKey.length > 0);

    if (![NSFileManager.defaultManager fileExistsAtPath:srcFilePath]) {
        DDLogError(@"%@ missing downloaded file.", self.logTag);
        return nil;
    }

    // TODO: Decrypt the file without loading it into memory.
    NSData *_Nullable srcData = [NSData dataWithContentsOfFile:srcFilePath];
    if (!srcData) {
        OWSProdLogAndFail(@"%@ could not load file into memory", self.logTag);
        return nil;
    }

    NSData *_Nullable dstData = [self decryptDataAsData:srcData encryptionKey:encryptionKey];
    return dstData;
}

- (nullable NSData *)decryptDataAsData:(NSData *)srcData encryptionKey:(NSData *)encryptionKey
{
    OWSAssert(srcData);
    OWSAssert(encryptionKey.length > 0);

    // TODO: Decrypt the data using key;

    return srcData;
}

#pragma mark - Compression

- (nullable NSData *)compressData:(NSData *)srcData
{
    OWSAssert(srcData);

    if (!srcData) {
        OWSProdLogAndFail(@"%@ missing unencrypted data.", self.logTag);
        return nil;
    }

    size_t srcLength = [srcData length];
    const uint8_t *srcBuffer = (const uint8_t *)[srcData bytes];
    if (!srcBuffer) {
        return nil;
    }
    // This assumes that dst will always be smaller than src.
    //
    // We slightly pad the buffer size to account for the worst case.
    uint8_t *dstBuffer = malloc(sizeof(uint8_t) * srcLength) + 64 * 1024;
    if (!dstBuffer) {
        return nil;
    }
    // TODO: Should we use COMPRESSION_LZFSE?
    size_t dstLength = compression_encode_buffer(dstBuffer, srcLength, srcBuffer, srcLength, NULL, COMPRESSION_LZFSE);
    NSData *compressedData = [NSData dataWithBytes:dstBuffer length:dstLength];
    DDLogVerbose(@"%@ compressed %zd -> %zd = %0.2f",
        self.logTag,
        srcLength,
        dstLength,
        (srcLength > 0 ? (dstLength / (CGFloat)srcLength) : 0));
    free(dstBuffer);

    return compressedData;
}

- (nullable NSData *)decompressData:(NSData *)srcData uncompressedDataLength:(NSUInteger)uncompressedDataLength
{
    OWSAssert(srcData);

    if (!srcData) {
        OWSProdLogAndFail(@"%@ missing unencrypted data.", self.logTag);
        return nil;
    }

    size_t srcLength = [srcData length];
    const uint8_t *srcBuffer = (const uint8_t *)[srcData bytes];
    if (!srcBuffer) {
        return nil;
    }
    // We pad the buffer to be defensive.
    uint8_t *dstBuffer = malloc(sizeof(uint8_t) * (uncompressedDataLength + 1024));
    if (!dstBuffer) {
        return nil;
    }
    // TODO: Should we use COMPRESSION_LZFSE?
    size_t dstLength = compression_decode_buffer(dstBuffer, srcLength, srcBuffer, srcLength, NULL, COMPRESSION_LZFSE);
    NSData *decompressedData = [NSData dataWithBytes:dstBuffer length:dstLength];
    OWSAssert(decompressedData.length == uncompressedDataLength);
    DDLogVerbose(@"%@ decompressed %zd -> %zd = %0.2f",
        self.logTag,
        srcLength,
        dstLength,
        (dstLength > 0 ? (srcLength / (CGFloat)dstLength) : 0));
    free(dstBuffer);

    return decompressedData;
}

@end

NS_ASSUME_NONNULL_END
