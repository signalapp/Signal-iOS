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
    @autoreleasepool {
        MultiprocessTest* test = [[MultiprocessTest alloc] init];
        [test run];
    }
    return 0;
}
