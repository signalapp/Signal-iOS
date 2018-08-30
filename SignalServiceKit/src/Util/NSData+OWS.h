//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import <AxolotlKit/NSData+SPK.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSData (OWS)

+ (NSData *)join:(NSArray<NSData *> *)datas;

- (NSData *)dataByAppendingData:(NSData *)data;

- (NSString *)hexadecimalString;

#pragma mark - Base64

+ (NSData *)dataFromBase64StringNoPadding:(NSString *)aString;
+ (NSData *)dataFromBase64String:(NSString *)aString;

- (NSString *)base64EncodedString;

@end

NS_ASSUME_NONNULL_END
