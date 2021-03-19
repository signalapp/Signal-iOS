//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@class ChainKey;

@protocol Chain <NSObject, NSSecureCoding>

-(ChainKey*)chainKey;
-(void)setChainKey:(ChainKey*)chainKey;

@end
