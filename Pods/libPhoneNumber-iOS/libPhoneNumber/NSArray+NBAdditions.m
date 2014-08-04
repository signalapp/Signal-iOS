//
//  NSArray+NBAdditions.m
//  libPhoneNumber
//
//  Created by Frane Bandov on 04.10.13.
//

#import "NSArray+NBAdditions.h"

@implementation NSArray (NBAdditions)

- (id)safeObjectAtIndex:(NSUInteger)index
{
    @synchronized(self)
    {
        if(index >= [self count]) return nil;
        
        id res = [self objectAtIndex:index];
        
        if (res == nil || (NSNull*)res == [NSNull null])
            return nil;
        
        return res;
    }
}

@end
