//
//  TSAdapterCacheManager.h
//  Signal
//
//  Created by Dylan Bourgeois on 03/01/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@class TSMessageAdapter;

@interface TSAdapterCacheManager : NSObject {
    NSCache *messageAdaptersCache;
}

@property (nonatomic, retain) NSCache *messageAdaptersCache;

+ (id)sharedManager;

- (void)cacheAdapter:(TSMessageAdapter *)adapter forInteractionId:(NSString *)identifier;
- (void)clearCacheEntryForInteractionId:(NSString *)identifier;
- (TSMessageAdapter *)adapterForInteractionId:(NSString *)identifier;
- (BOOL)containsCacheEntryForInteractionId:(NSString *)identifier;


@end
