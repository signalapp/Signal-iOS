#import "MIMETypeUtil.h"
#if TARGET_OS_IPHONE
#import "UIImage+contentTypes.h"
#endif


@implementation MIMETypeUtil

+ (NSDictionary *)supportedVideoMIMETypesToExtensionTypes {
    return @{
        @"video/3gpp" : @"3gp",
        @"video/3gpp2" : @"3g2",
        @"video/mp4" : @"mp4",
        @"video/quicktime" : @"mov",
        @"video/x-m4v" : @"m4v"
    };
}

+ (NSDictionary *)supportedAudioMIMETypesToExtensionTypes {
    return @{
        @"audio/x-m4p" : @"m4p",
        @"audio/x-m4b" : @"m4b",
        @"audio/x-m4a" : @"m4a",
        @"audio/wav" : @"wav",
        @"audio/x-wav" : @"wav",
        @"audio/x-mpeg" : @"mp3",
        @"audio/mpeg" : @"mp3",
        @"audio/mp4" : @"mp4",
        @"audio/mp3" : @"mp3",
        @"audio/mpeg3" : @"mp3",
        @"audio/x-mp3" : @"mp3",
        @"audio/x-mpeg3" : @"mp3",
        @"audio/amr" : @"amr",
        @"audio/aiff" : @"aiff",
        @"audio/x-aiff" : @"aiff",
        @"audio/3gpp2" : @"3g2",
        @"audio/3gpp" : @"3gp"
    };
}

+ (NSDictionary *)supportedImageMIMETypesToExtensionTypes {
    return @{
        @"image/jpeg" : @"jpeg",
        @"image/pjpeg" : @"jpeg",
        @"image/png" : @"png",
        @"image/tiff" : @"tif",
        @"image/x-tiff" : @"tif",
        @"image/bmp" : @"bmp",
        @"image/x-windows-bmp" : @"bmp"
    };
}

+ (NSDictionary *)supportedAnimatedMIMETypesToExtensionTypes {
    return @{
        @"image/gif" : @"gif",
    };
}

+ (NSDictionary *)supportedVideoExtensionTypesToMIMETypes {
    return @{
        @"3gp" : @"video/3gpp",
        @"3gpp" : @"video/3gpp",
        @"3gp2" : @"video/3gpp2",
        @"3gpp2" : @"video/3gpp2",
        @"mp4" : @"video/mp4",
        @"mov" : @"video/quicktime",
        @"mqv" : @"video/quicktime",
        @"m4v" : @"video/x-m4v"
    };
}
+ (NSDictionary *)supportedAudioExtensionTypesToMIMETypes {
    return @{
        @"3gp" : @"audio/3gpp",
        @"3gpp" : @"@audio/3gpp",
        @"3g2" : @"audio/3gpp2",
        @"3gp2" : @"audio/3gpp2",
        @"aiff" : @"audio/aiff",
        @"aif" : @"audio/aiff",
        @"aifc" : @"audio/aiff",
        @"cdda" : @"audio/aiff",
        @"amr" : @"audio/amr",
        @"mp3" : @"audio/mp3",
        @"swa" : @"audio/mp3",
        @"mp4" : @"audio/mp4",
        @"mpeg" : @"audio/mpeg",
        @"mpg" : @"audio/mpeg",
        @"wav" : @"audio/wav",
        @"bwf" : @"audio/wav",
        @"m4a" : @"audio/x-m4a",
        @"m4b" : @"audio/x-m4b",
        @"m4p" : @"audio/x-m4p"
    };
}

+ (NSDictionary *)supportedImageExtensionTypesToMIMETypes {
    return @{
        @"png" : @"image/png",
        @"x-png" : @"image/png",
        @"jfif" : @"image/jpeg",
        @"jfif" : @"image/pjpeg",
        @"jfif-tbnl" : @"image/jpeg",
        @"jpe" : @"image/jpeg",
        @"jpe" : @"image/pjpeg",
        @"jpeg" : @"image/jpeg",
        @"jpg" : @"image/jpeg",
        @"tif" : @"image/tiff",
        @"tiff" : @"image/tiff"
    };
}

+ (NSDictionary *)supportedAnimatedExtensionTypesToMIMETypes {
    return @{
        @"gif" : @"image/gif",
    };
}

+ (BOOL)isSupportedVideoMIMEType:(NSString *)contentType {
    return [[self supportedVideoMIMETypesToExtensionTypes] objectForKey:contentType] != nil;
}

+ (BOOL)isSupportedAudioMIMEType:(NSString *)contentType {
    return [[self supportedAudioMIMETypesToExtensionTypes] objectForKey:contentType] != nil;
}

+ (BOOL)isSupportedImageMIMEType:(NSString *)contentType {
    return [[self supportedImageMIMETypesToExtensionTypes] objectForKey:contentType] != nil;
}

+ (BOOL)isSupportedAnimatedMIMEType:(NSString *)contentType {
    return [[self supportedAnimatedMIMETypesToExtensionTypes] objectForKey:contentType] != nil;
}

+ (BOOL)isSupportedMIMEType:(NSString *)contentType {
    return [self isSupportedImageMIMEType:contentType] || [self isSupportedAudioMIMEType:contentType] ||
           [self isSupportedVideoMIMEType:contentType] || [self isSupportedAnimatedMIMEType:contentType];
}

+ (BOOL)isSupportedVideoFile:(NSString *)filePath {
    return [[self supportedVideoExtensionTypesToMIMETypes] objectForKey:[filePath pathExtension]] != nil;
}

+ (BOOL)isSupportedAudioFile:(NSString *)filePath {
    return [[self supportedAudioExtensionTypesToMIMETypes] objectForKey:[filePath pathExtension]] != nil;
}

+ (BOOL)isSupportedImageFile:(NSString *)filePath {
    return [[self supportedImageExtensionTypesToMIMETypes] objectForKey:[filePath pathExtension]] != nil;
}

+ (BOOL)isSupportedAnimatedFile:(NSString *)filePath {
    return [[self supportedAnimatedExtensionTypesToMIMETypes] objectForKey:[filePath pathExtension]] != nil;
}

+ (NSString *)getSupportedExtensionFromVideoMIMEType:(NSString *)supportedMIMEType {
    return [[self supportedVideoMIMETypesToExtensionTypes] objectForKey:supportedMIMEType];
}

+ (NSString *)getSupportedExtensionFromAudioMIMEType:(NSString *)supportedMIMEType {
    return [[self supportedAudioMIMETypesToExtensionTypes] objectForKey:supportedMIMEType];
}

+ (NSString *)getSupportedExtensionFromImageMIMEType:(NSString *)supportedMIMEType {
    return [[self supportedImageMIMETypesToExtensionTypes] objectForKey:supportedMIMEType];
}

+ (NSString *)getSupportedExtensionFromAnimatedMIMEType:(NSString *)supportedMIMEType {
    return [[self supportedAnimatedMIMETypesToExtensionTypes] objectForKey:supportedMIMEType];
}

+ (NSString *)getSupportedMIMETypeFromVideoFile:(NSString *)supportedVideoFile {
    return [[self supportedVideoExtensionTypesToMIMETypes] objectForKey:[supportedVideoFile pathExtension]];
}

+ (NSString *)getSupportedMIMETypeFromAudioFile:(NSString *)supportedAudioFile {
    return [[self supportedAudioExtensionTypesToMIMETypes] objectForKey:[supportedAudioFile pathExtension]];
}

+ (NSString *)getSupportedMIMETypeFromImageFile:(NSString *)supportedImageFile {
    return [[self supportedImageExtensionTypesToMIMETypes] objectForKey:[supportedImageFile pathExtension]];
}

+ (NSString *)getSupportedMIMETypeFromAnimatedFile:(NSString *)supportedAnimatedFile {
    return [[self supportedAnimatedExtensionTypesToMIMETypes] objectForKey:[supportedAnimatedFile pathExtension]];
}

#pragma mark full attachment utilities
+ (BOOL)isAnimated:(NSString *)contentType {
    return [MIMETypeUtil isSupportedAnimatedMIMEType:contentType];
}
+ (BOOL)isImage:(NSString *)contentType {
    return [MIMETypeUtil isSupportedImageMIMEType:contentType];
}

+ (BOOL)isVideo:(NSString *)contentType {
    return [MIMETypeUtil isSupportedVideoMIMEType:contentType];
}

+ (BOOL)isAudio:(NSString *)contentType {
    return [MIMETypeUtil isSupportedAudioMIMEType:contentType];
}

+ (NSString *)filePathForAttachment:(NSString *)uniqueId
                         ofMIMEType:(NSString *)contentType
                           inFolder:(NSString *)folder {
    if ([self isVideo:contentType]) {
        return [MIMETypeUtil filePathForVideo:uniqueId ofMIMEType:contentType inFolder:folder];
    } else if ([self isAudio:contentType]) {
        return [MIMETypeUtil filePathForAudio:uniqueId ofMIMEType:contentType inFolder:folder];
    } else if ([self isImage:contentType]) {
        return [MIMETypeUtil filePathForImage:uniqueId ofMIMEType:contentType inFolder:folder];
    } else if ([self isAnimated:contentType]) {
        return [MIMETypeUtil filePathForAnimated:uniqueId ofMIMEType:contentType inFolder:folder];
    }

    DDLogError(@"Got asked for path of file %@ which is unsupported", contentType);
    return nil;
}

+ (NSURL *)simLinkCorrectExtensionOfFile:(NSURL *)mediaURL ofMIMEType:(NSString *)contentType {
    if ([self isAudio:contentType]) {
        // Audio files in current framework require changing to have extension for player
        return [self changeFile:mediaURL
                toHaveExtension:[[self supportedAudioMIMETypesToExtensionTypes] objectForKey:contentType]];
    }
    return mediaURL;
}

+ (NSURL *)changeFile:(NSURL *)originalFile toHaveExtension:(NSString *)extension {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *newPath =
        [originalFile.URLByDeletingPathExtension.absoluteString stringByAppendingPathExtension:extension];
    if (![fileManager fileExistsAtPath:newPath]) {
        NSError *error = nil;
        [fileManager createSymbolicLinkAtPath:newPath withDestinationPath:[originalFile path] error:&error];
        return [NSURL URLWithString:newPath];
    }
    return originalFile;
}

+ (NSString *)filePathForImage:(NSString *)uniqueId ofMIMEType:(NSString *)contentType inFolder:(NSString *)folder {
    return [[folder stringByAppendingFormat:@"/%@", uniqueId]
        stringByAppendingPathExtension:[self getSupportedExtensionFromImageMIMEType:contentType]];
}

+ (NSString *)filePathForVideo:(NSString *)uniqueId ofMIMEType:(NSString *)contentType inFolder:(NSString *)folder {
    return [[folder stringByAppendingFormat:@"/%@", uniqueId]
        stringByAppendingPathExtension:[self getSupportedExtensionFromVideoMIMEType:contentType]];
}

+ (NSString *)filePathForAudio:(NSString *)uniqueId ofMIMEType:(NSString *)contentType inFolder:(NSString *)folder {
    return [[folder stringByAppendingFormat:@"/%@", uniqueId]
        stringByAppendingPathExtension:[self getSupportedExtensionFromAudioMIMEType:contentType]];
}

+ (NSString *)filePathForAnimated:(NSString *)uniqueId ofMIMEType:(NSString *)contentType inFolder:(NSString *)folder {
    return [[folder stringByAppendingFormat:@"/%@", uniqueId]
        stringByAppendingPathExtension:[self getSupportedExtensionFromAnimatedMIMEType:contentType]];
}

#if TARGET_OS_IPHONE

+ (NSString *)getSupportedImageMIMETypeFromImage:(UIImage *)image {
    return [image contentType];
}

+ (BOOL)getIsSupportedTypeFromImage:(UIImage *)image {
    return [image isSupportedImageType];
}

#endif

@end
