#import <Foundation/Foundation.h>

@interface MIMETypeUtil : NSObject

+ (BOOL)isSupportedMIMEType:(NSString *)contentType;
+ (BOOL)isSupportedVideoMIMEType:(NSString *)contentType;
+ (BOOL)isSupportedAudioMIMEType:(NSString *)contentType;
+ (BOOL)isSupportedImageMIMEType:(NSString *)contentType;
+ (BOOL)isSupportedAnimatedMIMEType:(NSString *)contentType;

+ (BOOL)isSupportedVideoFile:(NSString *)filePath;
+ (BOOL)isSupportedAudioFile:(NSString *)filePath;
+ (BOOL)isSupportedImageFile:(NSString *)filePath;
+ (BOOL)isSupportedAnimatedFile:(NSString *)filePath;

+ (NSString *)getSupportedExtensionFromVideoMIMEType:(NSString *)supportedMIMEType;
+ (NSString *)getSupportedExtensionFromAudioMIMEType:(NSString *)supportedMIMEType;
+ (NSString *)getSupportedExtensionFromImageMIMEType:(NSString *)supportedMIMEType;
+ (NSString *)getSupportedExtensionFromAnimatedMIMEType:(NSString *)supportedMIMEType;

+ (NSString *)getSupportedMIMETypeFromVideoFile:(NSString *)supportedVideoFile;
+ (NSString *)getSupportedMIMETypeFromAudioFile:(NSString *)supportedAudioFile;
+ (NSString *)getSupportedMIMETypeFromImageFile:(NSString *)supportedImageFile;
+ (NSString *)getSupportedMIMETypeFromAnimatedFile:(NSString *)supportedImageFile;

+ (BOOL)isAnimated:(NSString *)contentType;
+ (BOOL)isImage:(NSString *)contentType;
+ (BOOL)isVideo:(NSString *)contentType;
+ (BOOL)isAudio:(NSString *)contentType;

+ (NSString *)filePathForAttachment:(NSString *)uniqueId ofMIMEType:(NSString *)contentType inFolder:(NSString *)folder;
+ (NSString *)filePathForImage:(NSString *)uniqueId ofMIMEType:(NSString *)contentType inFolder:(NSString *)folder;
+ (NSString *)filePathForVideo:(NSString *)uniqueId ofMIMEType:(NSString *)contentType inFolder:(NSString *)folder;
+ (NSString *)filePathForAudio:(NSString *)uniqueId ofMIMEType:(NSString *)contentType inFolder:(NSString *)folder;
+ (NSString *)filePathForAnimated:(NSString *)uniqueId ofMIMEType:(NSString *)contentType inFolder:(NSString *)folder;

+ (NSURL *)simLinkCorrectExtensionOfFile:(NSURL *)mediaURL ofMIMEType:(NSString *)contentType;

#if TARGET_OS_IPHONE
+ (NSString *)getSupportedImageMIMETypeFromImage:(UIImage *)image;
+ (BOOL)getIsSupportedTypeFromImage:(UIImage *)image;
#endif

@end
