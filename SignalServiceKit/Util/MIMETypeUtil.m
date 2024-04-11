//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "MIMETypeUtil.h"
#import "OWSFileSystem.h"

#if TARGET_OS_IPHONE
#import <MobileCoreServices/MobileCoreServices.h>

#else
#import <CoreServices/CoreServices.h>

#endif
#import <SignalServiceKit/SignalServiceKit-Swift.h>

NS_ASSUME_NONNULL_BEGIN

NSString *const OWSMimeTypeApplicationOctetStream = @"application/octet-stream";
NSString *const OWSMimeTypeImagePng = @"image/png";
NSString *const OWSMimeTypeImageJpeg = @"image/jpeg";
NSString *const OWSMimeTypeImageGif = @"image/gif";
NSString *const OWSMimeTypeImageTiff1 = @"image/tiff";
NSString *const OWSMimeTypeImageTiff2 = @"image/x-tiff";
NSString *const OWSMimeTypeImageBmp1 = @"image/bmp";
NSString *const OWSMimeTypeImageBmp2 = @"image/x-windows-bmp";
NSString *const OWSMimeTypeImageWebp = @"image/webp";
NSString *const OWSMimeTypeImageHeic = @"image/heic";
NSString *const OWSMimeTypeImageHeif = @"image/heif";
NSString *const OWSMimeTypeOversizeTextMessage = @"text/x-signal-plain";
NSString *const OWSMimeTypeUnknownForTests = @"unknown/mimetype";
// TODO: We're still finalizing the MIME type.
NSString *const OWSMimeTypeLottieSticker = @"text/x-signal-sticker-lottie";
NSString *const OWSMimeTypeImageApng1 = @"image/apng";
NSString *const OWSMimeTypeImageApng2 = @"image/vnd.mozilla.apng";

NSString *const kOversizeTextAttachmentFileExtension = @"txt";
NSString *const kSyncMessageFileExtension = @"bin";

@implementation MIMETypeUtil

#pragma mark - Full attachment utilities

+ (nullable NSString *)filePathForAttachment:(NSString *)uniqueId
                                  ofMIMEType:(NSString *)contentType
                              sourceFilename:(nullable NSString *)sourceFilename
                                    inFolder:(NSString *)folder
{
    NSString *kDefaultFileExtension = @"bin";

    if (sourceFilename.length > 0) {
        NSString *normalizedFilename =
            [sourceFilename stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        // Ensure that the filename is a valid filesystem name,
        // replacing invalid characters with an underscore.
        for (NSCharacterSet *invalidCharacterSet in @[
                 [NSCharacterSet whitespaceAndNewlineCharacterSet],
                 [NSCharacterSet illegalCharacterSet],
                 [NSCharacterSet controlCharacterSet],
                 [NSCharacterSet characterSetWithCharactersInString:@"<>|\\:()&;?*/~"],
             ]) {
            normalizedFilename = [[normalizedFilename componentsSeparatedByCharactersInSet:invalidCharacterSet]
                componentsJoinedByString:@"_"];
        }

        // Remove leading periods to prevent hidden files,
        // "." and ".." special file names.
        while ([normalizedFilename hasPrefix:@"."]) {
            normalizedFilename = [normalizedFilename substringFromIndex:1];
        }

        NSString *fileExtension = [[normalizedFilename pathExtension]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *filenameWithoutExtension = [[[normalizedFilename lastPathComponent] stringByDeletingPathExtension]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

        // If the filename has not file extension, deduce one
        // from the MIME type.
        if (fileExtension.length < 1) {
            fileExtension = [MimeTypeUtil fileExtensionForMimeType:contentType];
            if (fileExtension.length < 1) {
                fileExtension = kDefaultFileExtension;
            }
        }
        fileExtension = [fileExtension lowercaseString];

        if (filenameWithoutExtension.length > 0) {
            // Store the file in a subdirectory whose name is the uniqueId of this attachment,
            // to avoid collisions between multiple attachments with the same name.
            NSString *attachmentFolderPath = [folder stringByAppendingPathComponent:uniqueId];
            if (![OWSFileSystem ensureDirectoryExists:attachmentFolderPath]) {
                return nil;
            }
            return [attachmentFolderPath
                stringByAppendingPathComponent:[NSString
                                                   stringWithFormat:@"%@.%@", filenameWithoutExtension, fileExtension]];
        }
    }

    if ([MimeTypeUtil isSupportedVideoMimeType:contentType]) {
        return [MIMETypeUtil filePathForVideo:uniqueId ofMIMEType:contentType inFolder:folder];
    } else if ([MimeTypeUtil isSupportedAudioMimeType:contentType]) {
        return [MIMETypeUtil filePathForAudio:uniqueId ofMIMEType:contentType inFolder:folder];
    } else if ([MimeTypeUtil isSupportedImageMimeType:contentType]) {
        return [MIMETypeUtil filePathForImage:uniqueId ofMIMEType:contentType inFolder:folder];
    } else if ([MimeTypeUtil isSupportedMaybeAnimatedMimeType:contentType]) {
        return [MIMETypeUtil filePathForAnimated:uniqueId ofMIMEType:contentType inFolder:folder];
    } else if ([MimeTypeUtil isSupportedBinaryDataMimeType:contentType]) {
        return [MIMETypeUtil filePathForBinaryData:uniqueId ofMIMEType:contentType inFolder:folder];
    } else if ([contentType isEqualToString:OWSMimeTypeOversizeTextMessage]) {
        // We need to use a ".txt" file extension since this file extension is used
        // by UIActivityViewController to determine which kinds of sharing are
        // appropriate for this text.
        // be used outside the app.
        return [self filePathForData:uniqueId withFileExtension:kOversizeTextAttachmentFileExtension inFolder:folder];
    } else if ([contentType isEqualToString:OWSMimeTypeUnknownForTests]) {
        // This file extension is arbitrary - it should never be exposed to the user or
        // be used outside the app.
        return [self filePathForData:uniqueId withFileExtension:@"unknown" inFolder:folder];
    }

    NSString *fileExtension = [MimeTypeUtil fileExtensionForMimeType:contentType];
    if (fileExtension) {
        return [self filePathForData:uniqueId withFileExtension:fileExtension inFolder:folder];
    }

    OWSLogError(@"Got asked for path of file %@ which is unsupported", contentType);
    // Use a fallback file extension.
    return [self filePathForData:uniqueId withFileExtension:kDefaultFileExtension inFolder:folder];
}

+ (NSString *)filePathForImage:(NSString *)uniqueId ofMIMEType:(NSString *)contentType inFolder:(NSString *)folder
{
    return [self filePathForData:uniqueId
               withFileExtension:[MimeTypeUtil getSupportedExtensionFromImageMimeType:contentType]
                        inFolder:folder];
}

+ (NSString *)filePathForVideo:(NSString *)uniqueId ofMIMEType:(NSString *)contentType inFolder:(NSString *)folder
{
    return [self filePathForData:uniqueId
               withFileExtension:[MimeTypeUtil getSupportedExtensionFromVideoMimeType:contentType]
                        inFolder:folder];
}

+ (NSString *)filePathForAudio:(NSString *)uniqueId ofMIMEType:(NSString *)contentType inFolder:(NSString *)folder
{
    return [self filePathForData:uniqueId
               withFileExtension:[MimeTypeUtil getSupportedExtensionFromAudioMimeType:contentType]
                        inFolder:folder];
}

+ (NSString *)filePathForAnimated:(NSString *)uniqueId ofMIMEType:(NSString *)contentType inFolder:(NSString *)folder
{
    return [self filePathForData:uniqueId
               withFileExtension:[MimeTypeUtil getSupportedExtensionFromAnimatedMimeType:contentType]
                        inFolder:folder];
}

+ (NSString *)filePathForBinaryData:(NSString *)uniqueId ofMIMEType:(NSString *)contentType inFolder:(NSString *)folder
{
    return [self filePathForData:uniqueId
               withFileExtension:[MimeTypeUtil getSupportedExtensionFromBinaryDataMimeType:contentType]
                        inFolder:folder];
}

+ (NSString *)filePathForData:(NSString *)uniqueId
            withFileExtension:(NSString *)fileExtension
                     inFolder:(NSString *)folder
{
    return [folder stringByAppendingPathComponent:[uniqueId stringByAppendingPathExtension:fileExtension]];
}

+ (NSSet<NSString *> *)utiTypesForMIMETypes:(NSArray *)mimeTypes
{
    NSMutableSet<NSString *> *result = [NSMutableSet new];
    for (NSString *mimeType in mimeTypes) {
        NSString *_Nullable utiType = [MimeTypeUtil utiTypeForMimeType:mimeType];
        if (!utiType) {
            OWSFailDebug(@"unknown utiType for mimetype: %@", mimeType);
            continue;
        }
        [result addObject:utiType];
    }
    return result;
}

+ (NSSet<NSString *> *)supportedVideoUTITypes
{
    static NSSet<NSString *> *result = nil;
    static dispatch_once_t onceToken;
    dispatch_once(
        &onceToken, ^{ result = [self utiTypesForMIMETypes:[MimeTypeUtil supportedVideoMimeTypesToExtensionTypes].allKeys]; });
    return result;
}

+ (NSSet<NSString *> *)supportedAudioUTITypes
{
    static NSSet<NSString *> *result = nil;
    static dispatch_once_t onceToken;
    dispatch_once(
        &onceToken, ^{ result = [self utiTypesForMIMETypes:[MimeTypeUtil supportedAudioMimeTypesToExtensionTypes].allKeys]; });
    return result;
}

+ (NSSet<NSString *> *)supportedInputImageUTITypes
{
    static NSSet<NSString *> *result = nil;
    static dispatch_once_t onceToken;
    dispatch_once(
        &onceToken, ^{ result = [self utiTypesForMIMETypes:[MimeTypeUtil supportedImageMimeTypesToExtensionTypes].allKeys]; });
    return result;
}

+ (NSSet<NSString *> *)supportedOutputImageUTITypes
{
    static NSSet<NSString *> *result = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray<NSString *> *imageMIMETypes =
            [[MimeTypeUtil supportedImageMimeTypesToExtensionTypes].allKeys mutableCopy];
        [imageMIMETypes removeObjectsInArray:@[
            OWSMimeTypeImageWebp,
            OWSMimeTypeImageHeic,
            OWSMimeTypeImageHeif,
        ]];
        result = [self utiTypesForMIMETypes:imageMIMETypes];
    });
    return result;
}

+ (NSSet<NSString *> *)supportedAnimatedImageUTITypes
{
    static NSSet<NSString *> *result = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken,
        ^{ result = [self utiTypesForMIMETypes:[MimeTypeUtil supportedMaybeAnimatedMimeTypesToExtensionTypes].allKeys]; });
    return result;
}

@end

NS_ASSUME_NONNULL_END
