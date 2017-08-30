//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (Image)

+ (BOOL)ows_isValidImageAtPath:(NSString *)filePath;
- (BOOL)ows_isValidImage;

@end
