//
//  TSInteraction.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSInteraction.h"

const struct TSMessageRelationships TSMessageRelationships = {
    .threadUniqueId = @"threadUniqueId",
};

const struct TSMessageEdges TSMessageEdges = {
    .thread = @"thread",
};

@implementation TSInteraction

- (instancetype)initWithTimestamp:(uint64_t)timestamp inThread:(TSThread*)thread{
    self = [super initWithUniqueId:[[self class] stringFromTimeStamp:timestamp]];
    
    if (self) {
        _uniqueThreadId = thread.uniqueId;
    }
    
    return self;
}


#pragma mark YapDatabaseRelationshipNode

- (NSArray *)yapDatabaseRelationshipEdges
{
    NSArray *edges = nil;
    if (self.uniqueThreadId) {
        YapDatabaseRelationshipEdge *threadEdge = [YapDatabaseRelationshipEdge edgeWithName:TSMessageEdges.thread
                                                                             destinationKey:self.uniqueThreadId
                                                                                 collection:[TSThread collection]
                                                                            nodeDeleteRules:YDB_DeleteSourceIfDestinationDeleted];
        edges = @[threadEdge];
    }
    
    return edges;
}

+ (NSString*)collection{
    return @"TSInteraction";
}

#pragma mark Date operations

- (uint64_t)identifierToTimestamp{
    NSNumberFormatter * f = [[NSNumberFormatter alloc] init];
    [f setNumberStyle:NSNumberFormatterNoStyle];
    NSNumber * myNumber = [f numberFromString:self.uniqueId];
    return [myNumber unsignedLongLongValue];
}

- (NSDate*)date{
    uint64_t milliseconds = [self identifierToTimestamp];
    uint64_t seconds      = milliseconds/1000;
    return [NSDate dateWithTimeIntervalSince1970:seconds];
}

- (UInt64)timeStamp{
    return [self identifierToTimestamp];
}

+ (NSString*)stringFromTimeStamp:(uint64_t)timestamp{
    return [[NSNumber numberWithUnsignedLongLong:timestamp] stringValue];
}

@end
