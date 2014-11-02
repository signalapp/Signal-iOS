//
//  DemoDataFactory.m
//  Signal
//
//  Created by Dylan Bourgeois on 27/10/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "DemoDataFactory.h"

@implementation DemoDataFactory

+(NSArray*)data {
    NSMutableArray* _mutableArray = [[NSMutableArray alloc]init];
    
    for (NSUInteger i=0;i<5;i++)
        [_mutableArray addObject:[DemoDataModel initModel:i]];
    
    return (NSArray*)_mutableArray;
}

+(NSArray*)makeFakeContacts
{
    NSMutableArray* _mutableArray = [[NSMutableArray alloc]init];
    
    for (NSUInteger i=0;i<5;i++)
        [_mutableArray addObject:[DemoDataModel initFakeContacts:i]];
    
    return (NSArray*)_mutableArray;
}

+(NSArray*)makeFakeCalls
{
    NSMutableArray* _mutableArray = [[NSMutableArray alloc]init];
    
    for (NSUInteger i=0;i<5;i++)
        [_mutableArray addObject:[DemoDataModel initRecentCall:i]];
    
    return (NSArray*)_mutableArray;
}
@end
