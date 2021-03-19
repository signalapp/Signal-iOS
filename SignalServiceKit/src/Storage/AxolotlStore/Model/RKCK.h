//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <SignalServiceKit/Chain.h>
#import <SignalServiceKit/RootKey.h>
#import <SignalServiceKit/SessionState.h>

@class ECKeyPair;

@interface RKCK : NSObject

@property (nonatomic,strong) RootKey  *rootKey;
@property (nonatomic,strong) ChainKey *chainKey;

-(instancetype) initWithRK:(RootKey*)rootKey CK:(ChainKey*)chainKey;

@end
