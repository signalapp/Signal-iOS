//
//  TSStorageManager+keyFromIntLong.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 08/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager+keyFromIntLong.h"

@implementation TSStorageManager (keyFromIntLong)

- (NSString *)keyFromInt:(int)integer {
    return [[NSNumber numberWithInteger:integer] stringValue];
}

@end
