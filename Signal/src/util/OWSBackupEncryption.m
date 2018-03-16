//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSBackupEncryption.h"
#import <Curve25519Kit/Randomness.h>
#import <SignalServiceKit/OWSFileSystem.h>

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

- (nullable NSString *)decryptFileAsTempFile:(NSString *)srcFilePath encryptionKey:(NSData *)encryptionKey
{
    OWSAssert(srcFilePath.length > 0);
    OWSAssert(encryptionKey.length > 0);

    // TODO: Decrypt the file without loading it into memory.
    NSData *_Nullable srcData = [NSData dataWithContentsOfFile:srcFilePath];
    if (!srcData) {
        OWSProdLogAndFail(@"%@ could not load file into memory", self.logTag);
        return nil;
    }

    NSData *_Nullable dstData = [self decryptDataAsData:srcData encryptionKey:encryptionKey];
    if (!dstData) {
        return nil;
    }

    NSString *dstFilePath = [self.jobTempDirPath stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    NSError *error;
    BOOL success = [dstData writeToFile:dstFilePath options:NSDataWritingAtomic error:&error];
    if (!success || error) {
        OWSProdLogAndFail(@"%@ error writing decrypted data: %@", self.logTag, error);
        return nil;
    }
    [OWSFileSystem protectFileOrFolderAtPath:dstFilePath];

    return dstFilePath;
}

- (nullable NSData *)decryptDataAsData:(NSData *)srcData encryptionKey:(NSData *)encryptionKey
{
    OWSAssert(srcData);
    OWSAssert(encryptionKey.length > 0);

    // TODO: Decrypt the data using key;

    return srcData;
}

@end

NS_ASSUME_NONNULL_END
