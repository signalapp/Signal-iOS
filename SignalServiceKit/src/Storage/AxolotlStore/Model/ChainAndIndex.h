//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <SignalServiceKit/ChainKey.h>

@interface ChainAndIndex : NSObject

@property id<Chain> chain;
@property int       index;

@end
