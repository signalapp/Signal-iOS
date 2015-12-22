//
//  NSData+ows_StripToken.h
//  Signal
//
//  Created by Frederic Jacobs on 14/04/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (ows_StripToken)

- (NSString *)ows_tripToken;

@end
