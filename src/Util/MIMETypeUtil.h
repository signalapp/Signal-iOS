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

+ (BOOL)isAnimated:(NSString *)contentType;
+ (BOOL)isImage:(NSString *)contentType;
+ (BOOL)isVideo:(NSString *)contentType;
+ (BOOL)isAudio:(NSString *)contentType;

// filename is optional and should not be trusted.
+ (NSString *)filePathForAttachment:(NSString *)uniqueId
                         ofMIMEType:(NSString *)contentType
                           filename:(nullable NSString *)filename
                           inFolder:(NSString *)folder;

+ (NSURL *)simLinkCorrectExtensionOfFile:(NSURL *)mediaURL ofMIMEType:(NSString *)contentType;

+ (NSSet<NSString *> *)supportedVideoUTITypes;
+ (NSSet<NSString *> *)supportedAudioUTITypes;
+ (NSSet<NSString *> *)supportedImageUTITypes;
+ (NSSet<NSString *> *)supportedAnimatedImageUTITypes;

+ (nullable NSString *)utiTypeForMIMEType:(NSString *)mimeType;
+ (nullable NSString *)utiTypeForFileExtension:(NSString *)fileExtension;
+ (nullable NSString *)fileExtensionForUTIType:(NSString *)utiType;
+ (nullable NSString *)fileExtensionForMIMEType:(NSString *)mimeType;

@end
