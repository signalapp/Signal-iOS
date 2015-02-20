#import "MIMETypeUtil.h"
#import "UIImage+contentTypes.h"

@implementation MIMETypeUtil

static NSDictionary *supportedVideoMIMETypesToExtensionTypes;
static NSDictionary *supportedAudioMIMETypesToExtensionTypes;
static NSDictionary *supportedImageMIMETypesToExtensionTypes;
static NSDictionary *supportedVideoExtensionTypesToMIMETypes;
static NSDictionary *supportedAudioExtensionTypesToMIMETypes;
static NSDictionary *supportedImageExtensionTypesToMIMETypes;

#pragma mark uses file extensions or MIME types only
+(void) initialize {
    // Initialize must be called before this class is used. Could later be in e.g. a .plist
    supportedVideoMIMETypesToExtensionTypes =@{@"video/3gpp":@"3gp",
                                                  @"video/3gpp2":@"3g2",
                                                  @"video/mp4":@"mp4",
                                                  @"video/quicktime":@"mov",
                                                  @"video/x-m4v":@"m4v"
                                                  };
    
    supportedAudioMIMETypesToExtensionTypes =   @{@"audio/x-m4p":@"m4p",
                                                  @"audio/x-m4b":@"m4b",
                                                  @"audio/x-m4a":@"m4a",
                                                  @"audio/wav":@"wav",
                                                  @"audio/x-wav":@"wav",
                                                  @"audio/x-mpeg":@"mp3",
                                                  @"audio/mpeg":@"mp3",
                                                  @"audio/mp4":@"mp4",
                                                  @"audio/mp3":@"mp3",
                                                  @"audio/mpeg3":@"mp3",
                                                  @"audio/x-mp3":@"mp3",
                                                  @"audio/x-mpeg3":@"mp3",
                                                  @"audio/amr":@"amr",
                                                  @"audio/aiff":@"aiff",
                                                  @"audio/x-aiff":@"aiff",
                                                  @"audio/3gpp2":@"3g2",
                                                  @"audio/3gpp":@"3gp"
                                                  };
    
    
    supportedImageMIMETypesToExtensionTypes =   @{@"image/jpeg":@"jpeg",
                                                  @"image/pjpeg":@"jpeg",
                                                  @"image/png":@"png",
                                                  @"image/gif":@"gif",
                                                  @"image/tiff":@"tif",
                                                  @"image/x-tiff":@"tif",
                                                  @"image/bmp":@"bmp",
                                                  @"image/x-windows-bmp":@"bmp"
                                                  };

    
    supportedVideoExtensionTypesToMIMETypes =   @{@"3gp":@"video/3gpp",
                                                  @"3gpp":@"video/3gpp",
                                                  @"3gp2":@"video/3gpp2",
                                                  @"3gpp2":@"video/3gpp2",
                                                  @"mp4":@"video/mp4",
                                                  @"mov":@"video/quicktime",
                                                  @"mqv":@"video/quicktime",
                                                  @"m4v":@"video/x-m4v"
                                                  };
    
    supportedAudioExtensionTypesToMIMETypes =   @{@"3gp":@"audio/3gpp",
                                                  @"3gpp":@"@audio/3gpp",
                                                  @"3g2":@"audio/3gpp2",
                                                  @"3gp2":@"audio/3gpp2",
                                                  @"aiff":@"audio/aiff",
                                                  @"aif":@"audio/aiff",
                                                  @"aifc":@"audio/aiff",
                                                  @"cdda":@"audio/aiff",
                                                  @"amr":@"audio/amr",
                                                  @"mp3":@"audio/mp3",
                                                  @"swa":@"audio/mp3",
                                                  @"mp4":@"audio/mp4",
                                                  @"mpeg":@"audio/mpeg",
                                                  @"mpg":@"audio/mpeg",
                                                  @"wav":@"audio/wav",
                                                  @"bwf":@"audio/wav",
                                                  @"m4a":@"audio/x-m4a",
                                                  @"m4b":@"audio/x-m4b",
                                                  @"m4p":@"audio/x-m4p"
                                                  };
    
    supportedImageExtensionTypesToMIMETypes = @{@"png":@"image/png",
                                                @"x-png":@"image/png",
                                                @"jfif":@"image/jpeg",
                                                @"jfif":@"image/pjpeg",
                                                @"jfif-tbnl":@"image/jpeg",
                                                @"jpe":@"image/jpeg",
                                                @"jpe":@"image/pjpeg",
                                                @"jpeg":@"image/jpeg",
                                                @"jpg":@"image/jpeg",
                                                @"gif":@"image/gif",
                                                @"tif":@"image/tiff",
                                                @"tiff":@"image/tiff"
                                                };
}

+(BOOL) isSupportedVideoMIMEType:(NSString*)contentType {
    return [supportedVideoMIMETypesToExtensionTypes objectForKey:contentType]!=nil;
}

+(BOOL) isSupportedAudioMIMEType:(NSString*)contentType {
    return [supportedAudioMIMETypesToExtensionTypes objectForKey:contentType]!=nil;
}

+(BOOL) isSupportedImageMIMEType:(NSString*)contentType {
    return [supportedImageMIMETypesToExtensionTypes objectForKey:contentType]!=nil;
}

+(BOOL) isSupportedMIMEType:(NSString*)contentType {
    return [self isSupportedImageMIMEType:contentType] || [self isSupportedAudioMIMEType:contentType] || [self isSupportedVideoMIMEType:contentType];
}

+(BOOL) isSupportedVideoFile:(NSString*) filePath {
    return [supportedVideoExtensionTypesToMIMETypes objectForKey:[filePath pathExtension]]!=nil;
}

+(BOOL) isSupportedAudioFile:(NSString*) filePath  {
    return [supportedAudioExtensionTypesToMIMETypes objectForKey:[filePath pathExtension]]!=nil;
}

+(BOOL) isSupportedImageFile:(NSString*) filePath  {
    return [supportedImageExtensionTypesToMIMETypes objectForKey:[filePath pathExtension]]!=nil;
}

+(NSString*) getSupportedExtensionFromVideoMIMEType:(NSString*)supportedMIMEType {
    return [supportedVideoMIMETypesToExtensionTypes objectForKey:supportedMIMEType];
}

+(NSString*) getSupportedExtensionFromAudioMIMEType:(NSString*)supportedMIMEType {
	return [supportedAudioMIMETypesToExtensionTypes objectForKey:supportedMIMEType];
}

+(NSString*) getSupportedExtensionFromImageMIMEType:(NSString*)supportedMIMEType {
    return [supportedImageMIMETypesToExtensionTypes objectForKey:supportedMIMEType];
}

+(NSString*) getSupportedMIMETypeFromVideoFile:(NSString*)supportedVideoFile {
    return [supportedVideoExtensionTypesToMIMETypes objectForKey:[supportedVideoFile pathExtension]];
} 

+(NSString*) getSupportedMIMETypeFromAudioFile:(NSString*)supportedAudioFile {
	return [supportedAudioExtensionTypesToMIMETypes objectForKey:[supportedAudioFile pathExtension]];
}

+(NSString*) getSupportedMIMETypeFromImageFile:(NSString*)supportedImageFile {
    return [supportedImageExtensionTypesToMIMETypes objectForKey:[supportedImageFile pathExtension]];
}

#pragma mark uses bytes
+(NSString*) getSupportedImageMIMETypeFromImage:(UIImage*)image {
	return [image contentType];
}

+(BOOL) getIsSupportedTypeFromImage:(UIImage*)image {
	return [image isSupportedImageType];
}

#pragma mark full attachment utilities
+ (BOOL)isImage:(NSString*)contentType {
    return [MIMETypeUtil isSupportedImageMIMEType:contentType];
}

+ (BOOL)isVideo:(NSString*)contentType {
    return [MIMETypeUtil isSupportedVideoMIMEType:contentType];
}

+(BOOL)isAudio:(NSString*)contentType {
    return [MIMETypeUtil isSupportedAudioMIMEType:contentType];
}

+ (NSString*)filePathForAttachment:(NSString*)uniqueId ofMIMEType:(NSString*)contentType inFolder:(NSString*)folder {
    if ([self isVideo:contentType]){
        return [MIMETypeUtil filePathForVideo:uniqueId ofMIMEType:contentType inFolder:folder];
    }
    else if([self isAudio:contentType]) {
        return [MIMETypeUtil filePathForAudio:uniqueId ofMIMEType:contentType inFolder:folder];
    }
    else if([self isImage:contentType]){
        return [MIMETypeUtil filePathForImage:uniqueId ofMIMEType:contentType inFolder:folder];
    }
    
    DDLogError(@"Got asked for path of file %@ which is unsupported", contentType);
    return nil;
}

+(NSURL*)  simLinkCorrectExtensionOfFile:(NSURL*)mediaURL ofMIMEType:(NSString*)contentType  {
    if([self isAudio:contentType]) {
        // Audio files in current framework require changing to have extension for player
        return [self changeFile:mediaURL toHaveExtension:[supportedAudioMIMETypesToExtensionTypes objectForKey:contentType]];
    }
    return mediaURL;
}

+(NSURL*) changeFile:(NSURL*)originalFile toHaveExtension:(NSString*)extension {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString* newPath = [originalFile.URLByDeletingPathExtension.absoluteString stringByAppendingPathExtension:extension];
    if (![fileManager fileExistsAtPath:newPath]) {
        NSError *error = nil;
        [fileManager createSymbolicLinkAtPath:newPath withDestinationPath:[originalFile path] error: &error];
        return [NSURL URLWithString:newPath];
    }
    return originalFile;
}

+ (NSString*)filePathForImage:(NSString*)uniqueId ofMIMEType:(NSString*)contentType inFolder:(NSString*)folder{
    return [[folder stringByAppendingFormat:@"/%@",uniqueId] stringByAppendingPathExtension:[self getSupportedExtensionFromImageMIMEType:contentType]];
}

+ (NSString*)filePathForVideo:(NSString*)uniqueId ofMIMEType:(NSString*)contentType inFolder:(NSString*)folder{
    return [[folder stringByAppendingFormat:@"/%@",uniqueId] stringByAppendingPathExtension:[self getSupportedExtensionFromVideoMIMEType:contentType]];
}

+ (NSString*)filePathForAudio:(NSString*)uniqueId ofMIMEType:(NSString*)contentType inFolder:(NSString*)folder{
    return [[folder stringByAppendingFormat:@"/%@",uniqueId] stringByAppendingPathExtension:[self getSupportedExtensionFromAudioMIMEType:contentType]];
}

@end
