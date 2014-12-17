//
//  TSAttachementPointer.h
//  Signal
//
//  Created by Frederic Jacobs on 17/12/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "TSAttachement.h"

@interface TSAttachementPointer : TSAttachement

- (instancetype)initWithIdentifier:(uint64_t)identifier
                               key:(NSData*)key
                       contentType:(NSString*)contentType
                             relay:(NSString*)relay;

@property NSString *relay;

@end
