//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@interface NSData (Base64)

+ (NSData *)dataFromBase64StringNoPadding:(NSString *)aString;
+ (NSData *)dataFromBase64String:(NSString *)aString;

- (NSString *)base64EncodedString;

@end
