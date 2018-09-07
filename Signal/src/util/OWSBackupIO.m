//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupIO.h"
#import <Curve25519Kit/Randomness.h>
#import <SignalServiceKit/OWSFileSystem.h>

@import Compression;

NS_ASSUME_NONNULL_BEGIN

// TODO:
static const NSUInteger kOWSBackupKeyLength = 32;

// LZMA algorithm significantly outperforms the other compressionlib options
// for our database snapshots and is a widely adopted standard.
static const compression_algorithm SignalCompressionAlgorithm = COMPRESSION_LZMA;

@implementation OWSBackupEncryptedItem

@end

#pragma mark -

@interface OWSBackupIO ()

@property (nonatomic) NSString *jobTempDirPath;

@end

#pragma mark -

@implementation OWSBackupIO

- (instancetype)initWithJobTempDirPath:(NSString *)jobTempDirPath
{
    if (!(self = [super init])) {
        return self;
    }

    self.jobTempDirPath = jobTempDirPath;

    return self;
}

- (NSString *)generateTempFilePath
{
    return [self.jobTempDirPath stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
}

- (nullable NSString *)createTempFile
{
    NSString *filePath = [self generateTempFilePath];
    if (![OWSFileSystem ensureFileExists:filePath]) {
        OWSFailDebug(@"could not create temp file.");
        return nil;
    }
    return filePath;
}

#pragma mark - Encrypt

- (nullable OWSBackupEncryptedItem *)encryptFileAsTempFile:(NSString *)srcFilePath
{
    OWSAssertDebug(srcFilePath.length > 0);

    NSData *encryptionKey = [Randomness generateRandomBytes:(int)kOWSBackupKeyLength];

    return [self encryptFileAsTempFile:srcFilePath encryptionKey:encryptionKey];
}

- (nullable OWSBackupEncryptedItem *)encryptFileAsTempFile:(NSString *)srcFilePath encryptionKey:(NSData *)encryptionKey
{
    OWSAssertDebug(srcFilePath.length > 0);
    OWSAssertDebug(encryptionKey.length > 0);

    @autoreleasepool {

        // TODO: Encrypt the file without loading it into memory.
        NSData *_Nullable srcData = [NSData dataWithContentsOfFile:srcFilePath];
        if (srcData.length < 1) {
            OWSFailDebug(@"could not load file into memory for encryption.");
            return nil;
        }
        return [self encryptDataAsTempFile:srcData encryptionKey:encryptionKey];
    }
}

- (nullable OWSBackupEncryptedItem *)encryptDataAsTempFile:(NSData *)srcData
{
    OWSAssertDebug(srcData);

    NSData *encryptionKey = [Randomness generateRandomBytes:(int)kOWSBackupKeyLength];

    return [self encryptDataAsTempFile:srcData encryptionKey:encryptionKey];
}

- (nullable OWSBackupEncryptedItem *)encryptDataAsTempFile:(NSData *)unencryptedData
                                             encryptionKey:(NSData *)encryptionKey
{
    OWSAssertDebug(unencryptedData);
    OWSAssertDebug(encryptionKey.length > 0);

    @autoreleasepool {

        // TODO: Encrypt the data using key;
        NSData *encryptedData = unencryptedData;

        NSString *_Nullable dstFilePath = [self createTempFile];
        if (!dstFilePath) {
            return nil;
        }
        NSError *error;
        BOOL success = [encryptedData writeToFile:dstFilePath options:NSDataWritingAtomic error:&error];
        if (!success || error) {
            OWSFailDebug(@"error writing encrypted data: %@", error);
            return nil;
        }
        [OWSFileSystem protectFileOrFolderAtPath:dstFilePath];
        OWSBackupEncryptedItem *item = [OWSBackupEncryptedItem new];
        item.filePath = dstFilePath;
        item.encryptionKey = encryptionKey;
        return item;
    }
}

#pragma mark - Decrypt

- (BOOL)decryptFileAsFile:(NSString *)srcFilePath
              dstFilePath:(NSString *)dstFilePath
            encryptionKey:(NSData *)encryptionKey
{
    OWSAssertDebug(srcFilePath.length > 0);
    OWSAssertDebug(encryptionKey.length > 0);

    @autoreleasepool {

        // TODO: Decrypt the file without loading it into memory.
        NSData *data = [self decryptFileAsData:srcFilePath encryptionKey:encryptionKey];

        if (data.length < 1) {
            return NO;
        }

        NSError *error;
        BOOL success = [data writeToFile:dstFilePath options:NSDataWritingAtomic error:&error];
        if (!success || error) {
            OWSFailDebug(@"error writing decrypted data: %@", error);
            return NO;
        }
        [OWSFileSystem protectFileOrFolderAtPath:dstFilePath];

        return YES;
    }
}

- (nullable NSData *)decryptFileAsData:(NSString *)srcFilePath encryptionKey:(NSData *)encryptionKey
{
    OWSAssertDebug(srcFilePath.length > 0);
    OWSAssertDebug(encryptionKey.length > 0);

    @autoreleasepool {

        if (![NSFileManager.defaultManager fileExistsAtPath:srcFilePath]) {
            OWSLogError(@"missing downloaded file.");
            return nil;
        }

        NSData *_Nullable srcData = [NSData dataWithContentsOfFile:srcFilePath];
        if (srcData.length < 1) {
            OWSFailDebug(@"could not load file into memory for decryption.");
            return nil;
        }

        NSData *_Nullable dstData = [self decryptDataAsData:srcData encryptionKey:encryptionKey];
        return dstData;
    }
}

- (nullable NSData *)decryptDataAsData:(NSData *)encryptedData encryptionKey:(NSData *)encryptionKey
{
    OWSAssertDebug(encryptedData);
    OWSAssertDebug(encryptionKey.length > 0);

    @autoreleasepool {

        // TODO: Decrypt the data using key;
        NSData *unencryptedData = encryptedData;

        return unencryptedData;
    }
}

#pragma mark - Compression

- (nullable NSData *)compressData:(NSData *)srcData
{
    OWSAssertDebug(srcData);

    @autoreleasepool {

        if (!srcData) {
            OWSFailDebug(@"missing unencrypted data.");
            return nil;
        }

        size_t srcLength = [srcData length];

        // This assumes that dst will always be smaller than src.
        //
        // We slightly pad the buffer size to account for the worst case.
        size_t dstBufferLength = srcLength + 64 * 1024;
        NSMutableData *dstBufferData = [NSMutableData dataWithLength:dstBufferLength];
        if (!dstBufferData) {
            OWSFailDebug(@"Failed to allocate buffer.");
            return nil;
        }

        size_t dstLength = compression_encode_buffer(
            dstBufferData.mutableBytes, dstBufferLength, srcData.bytes, srcLength, NULL, SignalCompressionAlgorithm);
        NSData *compressedData = [dstBufferData subdataWithRange:NSMakeRange(0, dstLength)];

        OWSLogVerbose(@"compressed %zd -> %zd = %0.2f",
            srcLength,
            dstLength,
            (srcLength > 0 ? (dstLength / (CGFloat)srcLength) : 0));

        return compressedData;
    }
}

- (nullable NSData *)decompressData:(NSData *)srcData uncompressedDataLength:(NSUInteger)uncompressedDataLength
{
    OWSAssertDebug(srcData);

    @autoreleasepool {

        if (!srcData) {
            OWSFailDebug(@"missing unencrypted data.");
            return nil;
        }

        size_t srcLength = [srcData length];

        // We pad the buffer to be defensive.
        size_t dstBufferLength = uncompressedDataLength + 1024;
        NSMutableData *dstBufferData = [NSMutableData dataWithLength:dstBufferLength];
        if (!dstBufferData) {
            OWSFailDebug(@"Failed to allocate buffer.");
            return nil;
        }

        size_t dstLength = compression_decode_buffer(
            dstBufferData.mutableBytes, dstBufferLength, srcData.bytes, srcLength, NULL, SignalCompressionAlgorithm);
        NSData *decompressedData = [dstBufferData subdataWithRange:NSMakeRange(0, dstLength)];
        OWSAssertDebug(decompressedData.length == uncompressedDataLength);
        OWSLogVerbose(@"decompressed %zd -> %zd = %0.2f",
            srcLength,
            dstLength,
            (dstLength > 0 ? (srcLength / (CGFloat)dstLength) : 0));

        return decompressedData;
    }
}

@end

NS_ASSUME_NONNULL_END
