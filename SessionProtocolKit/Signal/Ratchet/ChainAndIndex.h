//
//  ChainAndIndex.h
//  AxolotlKit
//
//  Created by Frederic Jacobs on 21/09/14.
//  Copyright (c) 2014 Frederic Jacobs. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ChainKey.h"

@interface ChainAndIndex : NSObject

@property id<Chain> chain;
@property int       index;

@end
