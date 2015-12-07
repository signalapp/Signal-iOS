//
//  TSStorageManager+keyFromIntLong.h
//  TextSecureKit
//
//  Created by Frederic Jacobs on 08/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSStorageManager.h"

@interface TSStorageManager (keyFromIntLong)

- (NSString *)keyFromInt:(int)integer;

@end
