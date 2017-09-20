//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@interface NSData (Image)

+ (BOOL)ows_isValidImageAtPath:(NSString *)filePath;
- (BOOL)ows_isValidImage;

@end
