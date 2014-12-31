//
//  TSAdapterCacheManager.m
//  Signal
//
//  Created by Dylan Bourgeois on 03/01/15.
//  Copyright (c) 2015 Open Whisper Systems. All rights reserved.
//

#import "TSAdapterCacheManager.h"
#import "TSMessageAdapter.h"

@implementation TSAdapterCacheManager

@synthesize messageAdaptersCache;

+ (id)sharedManager {
    static TSAdapterCacheManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    
    return sharedManager;
}

- (id)init {
    if (self = [super init]) {
        messageAdaptersCache = [[NSCache alloc]init];
    }
    return self;
}

- (void)cacheAdapter:(TSMessageAdapter*)adapter forInteractionId:(NSString*)identifier
{
    NSParameterAssert(adapter);
    NSParameterAssert(identifier);
    [messageAdaptersCache setObject:adapter forKey:identifier];
}

-(void)clearCacheEntryForInteractionId:(NSString*)identifier
{
    NSParameterAssert(identifier);
    [messageAdaptersCache removeObjectForKey:identifier];
}

-(TSMessageAdapter*)adapterForInteractionId:(NSString*)identifier
{
    NSParameterAssert(identifier);
    return [messageAdaptersCache objectForKey:identifier];
}

-(BOOL)containsCacheEntryForInteractionId:(NSString*)identifier
{
    return [messageAdaptersCache objectForKey:identifier] != nil;
}

@end
