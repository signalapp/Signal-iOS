//
//  Chain.h
//  AxolotlKit
//
//  Created by Frederic Jacobs on 02/09/14.
//  Copyright (c) 2014 Frederic Jacobs. All rights reserved.
//

#import <Foundation/Foundation.h>
@class ChainKey;

@protocol Chain <NSObject, NSSecureCoding>

-(ChainKey*)chainKey;
-(void)setChainKey:(ChainKey*)chainKey;

@end
