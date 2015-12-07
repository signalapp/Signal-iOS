//
//  UIImage+contentTypes.h
//  Signal
//
//  Created by Frederic Jacobs on 21/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIImage (contentTypes)

- (NSString *)contentType;
- (BOOL)isSupportedImageType;

@end
