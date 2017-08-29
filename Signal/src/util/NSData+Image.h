//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (Image)

+ (BOOL)isValidImageAtPath:(NSString *)filePath;
- (BOOL)isValidImage;

@end
