//
//  main.m
//  MultiprocessApp
//
//  Created by Jeremie Girault on 15/02/2016.
//  Copyright © 2016 Robbie Hanson. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MultiprocessTest.h"

int main(int argc, const char * argv[]) {
    
    NSString *name;
    BOOL specialBehavior = false;
    
    if (argc <= 1) {
        name = @"A";
    }
    else {
        name = [NSString stringWithUTF8String:argv[1]];
    }
    
    if (argc == 3) {
        NSLog(@"Special flag set");
        specialBehavior = true;
    }
    
    @autoreleasepool {
        MultiprocessTest* test = [[MultiprocessTest alloc] init];
        [test run:name specialBehavior:specialBehavior];
    }
    return 0;
}
