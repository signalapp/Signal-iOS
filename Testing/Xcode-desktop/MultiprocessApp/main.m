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
    if (argc <= 1) {
        name = @"A";
    }
    else {
        name = [NSString stringWithUTF8String:argv[1]];
    }
    
    @autoreleasepool {
        MultiprocessTest* test = [[MultiprocessTest alloc] init];
        [test run:name];
    }
    return 0;
}
