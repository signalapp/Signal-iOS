//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const OWSMimeTypeApplicationOctetStream;
extern NSString *const OWSMimeTypeApplicationZip;
extern NSString *const OWSMimeTypeImagePng;
extern NSString *const OWSMimeTypeImageJpeg;
extern NSString *const OWSMimeTypeImageGif;
extern NSString *const OWSMimeTypeImageTiff1;
extern NSString *const OWSMimeTypeImageTiff2;
extern NSString *const OWSMimeTypeImageBmp1;
extern NSString *const OWSMimeTypeImageBmp2;
extern NSString *const OWSMimeTypeImageWebp;
extern NSString *const OWSMimeTypeImageHeic;
extern NSString *const OWSMimeTypeImageHeif;
extern NSString *const OWSMimeTypePdf;
extern NSString *const OWSMimeTypeOversizeTextMessage;
extern NSString *const OWSMimeTypeProtobuf;
extern NSString *const OWSMimeTypeJson;
extern NSString *const OWSMimeTypeLottieSticker;
extern NSString *const OWSMimeTypeImageApng1;
extern NSString *const OWSMimeTypeImageApng2;
extern NSString *const OWSMimeTypeUnknownForTests;

extern NSString *const kOversizeTextAttachmentUTI;
extern NSString *const kOversizeTextAttachmentFileExtension;
extern NSString *const kUnknownTestAttachmentUTI;
extern NSString *const kSyncMessageFileExtension;
extern NSString *const kLottieStickerFileExtension;

@interface MIMETypeUtil : NSObject

+ (BOOL)isSupportedVideoMIMEType:(NSString *)contentType;
+ (BOOL)isSupportedAudioMIMEType:(NSString *)contentType;
+ (BOOL)isSupportedImageMIMEType:(NSString *)contentType;
+ (BOOL)isSupportedAnimatedMIMEType:(NSString *)contentType;

+ (BOOL)isSupportedVideoFile:(NSString *)filePath;
+ (BOOL)isSupportedAudioFile:(NSString *)filePath;
+ (BOOL)isSupportedImageFile:(NSString *)filePath;
+ (BOOL)isSupportedAnimatedFile:(NSString *)filePath;

+ (nullable NSString *)getSupportedExtensionFromVideoMIMEType:(NSString *)supportedMIMEType;
+ (nullable NSString *)getSupportedExtensionFromAudioMIMEType:(NSString *)supportedMIMEType;
+ (nullable NSString *)getSupportedExtensionFromImageMIMEType:(NSString *)supportedMIMEType;
+ (nullable NSString *)getSupportedExtensionFromAnimatedMIMEType:(NSString *)supportedMIMEType;

+ (BOOL)isAnimated:(NSString *)contentType;
+ (BOOL)isImage:(NSString *)contentType;
+ (BOOL)isVideo:(NSString *)contentType;
+ (BOOL)isAudio:(NSString *)contentType;
+ (BOOL)isVisualMedia:(NSString *)contentType;

// filename is optional and should not be trusted.
+ (nullable NSString *)filePathForAttachment:(NSString *)uniqueId
                                  ofMIMEType:(NSString *)contentType
                              sourceFilename:(nullable NSString *)sourceFilename
                                    inFolder:(NSString *)folder;

+ (NSSet<NSString *> *)supportedVideoUTITypes;
+ (NSSet<NSString *> *)supportedAudioUTITypes;
+ (NSSet<NSString *> *)supportedInputImageUTITypes;
+ (NSSet<NSString *> *)supportedOutputImageUTITypes;
+ (NSSet<NSString *> *)supportedAnimatedImageUTITypes;

+ (nullable NSString *)utiTypeForMIMEType:(NSString *)mimeType;
+ (nullable NSString *)utiTypeForFileExtension:(NSString *)fileExtension;
+ (nullable NSString *)fileExtensionForUTIType:(NSString *)utiType;
+ (nullable NSString *)fileExtensionForMIMEType:(NSString *)mimeType;
+ (nullable NSString *)mimeTypeForFileExtension:(NSString *)fileExtension;

@end

NS_ASSUME_NONNULL_END
