//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

extern NSString *const OWSMimeTypeApplicationOctetStream;
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
extern NSString *const OWSMimeTypeOversizeTextMessage;
extern NSString *const OWSMimeTypeLottieSticker;
extern NSString *const OWSMimeTypeImageApng1;
extern NSString *const OWSMimeTypeImageApng2;
extern NSString *const OWSMimeTypeUnknownForTests;

extern NSString *const kOversizeTextAttachmentFileExtension;
extern NSString *const kSyncMessageFileExtension;

@interface MIMETypeUtil : NSObject

// filename is optional and should not be trusted.
+ (nullable NSString *)filePathForAttachment:(NSString *)uniqueId
                                  ofMIMEType:(NSString *)contentType
                              sourceFilename:(nullable NSString *)sourceFilename
                                    inFolder:(NSString *)folder;

@end

NS_ASSUME_NONNULL_END
