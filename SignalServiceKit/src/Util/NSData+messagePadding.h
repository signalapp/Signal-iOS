//
//  NSData+messagePadding.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 15/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (messagePadding)

- (NSData *)removePadding;

- (NSData *)paddedMessageBody;

@end
