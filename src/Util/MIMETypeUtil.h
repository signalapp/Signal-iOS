//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

extern NSString *const OWSMimeTypeApplicationOctetStream;
extern NSString *const OWSMimeTypeImagePng;
extern NSString *const OWSMimeTypeOversizeTextMessage;
extern NSString *const OWSMimeTypeUnknownForTests;

@interface MIMETypeUtil : NSObject

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

+ (NSSet<NSString *> *)supportedVideoUTITypes;
+ (NSSet<NSString *> *)supportedAudioUTITypes;
+ (NSSet<NSString *> *)supportedImageUTITypes;
+ (NSSet<NSString *> *)supportedAnimatedImageUTITypes;

+ (NSString *)utiTypeForMIMEType:(NSString *)mimeType;
+ (NSString *)fileExtensionForUTIType:(NSString *)utiType;
+ (NSString *)fileExtensionForMIMEType:(NSString *)mimeType;

@end
