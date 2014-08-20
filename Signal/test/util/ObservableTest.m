#import <XCTest/XCTest.h>
#import "ObservableValue.h"
#import "TestUtil.h"

@interface ObservableTest : XCTestCase
@end

@implementation ObservableTest

-(void) testObservableAddRemove {
    ObservableValueController* s = [ObservableValueController observableValueControllerWithInitialValue:@""];
    ObservableValue* t = s;
    NSMutableArray* a = [NSMutableArray array];
    TOCCancelTokenSource* c = [TOCCancelTokenSource new];
    
    [t watchLatestValueOnArbitraryThread:^(id value) {[a addObject:value];}
                          untilCancelled:c.token];
    
    test([a isEqualToArray:@[@""]]);
    [s updateValue:@5];
    test([a isEqualToArray:(@[@"", @5])]);
    [s updateValue:@7];
    test([a isEqualToArray:(@[@"", @5, @7])]);
    [c cancel];
    [s updateValue:@11];
    test([a isEqualToArray:(@[@"", @5, @7])]);
}
-(void) testObservableAddAdd {
    ObservableValueController* s = [ObservableValueController observableValueControllerWithInitialValue:@""];
    ObservableValue* t = s;
    NSMutableArray* a = [NSMutableArray array];
    TOCCancelTokenSource* c = [TOCCancelTokenSource new];
    
    [t watchLatestValueOnArbitraryThread:^(id value) {[a addObject:value];}
                          untilCancelled:c.token];
    [t watchLatestValueOnArbitraryThread:^(id value) {[a addObject:value];}
                          untilCancelled:c.token];
    [t watchLatestValueOnArbitraryThread:^(id value) {[a addObject:value];}
                          untilCancelled:c.token];
    
    test([a isEqualToArray:(@[@"", @"", @""])]);
    [s updateValue:@5];
    test([a isEqualToArray:(@[@"", @"", @"", @5, @5, @5])]);
}
-(void) testObservableRedundantSetIgnored {
    id v1 = @"";
    id v2 = nil;
    id v3 = @1;
    
    ObservableValueController* s = [ObservableValueController observableValueControllerWithInitialValue:v1];
    ObservableValue* t = s;
    __block id latest = nil;
    __block int count = 0;
    [t watchLatestValueOnArbitraryThread:^(id value) {latest = value;count++;}
                          untilCancelled:nil];

    test(latest == v1);
    test(count == 1);

    [s updateValue:v1];
    test(latest == v1);
    test(count == 1);
    
    [s updateValue:v2];
    test(latest == v2);
    test(count == 2);
    
    [s updateValue:v2];
    test(latest == v2);
    test(count == 2);

    [s updateValue:v1];
    test(latest == v1);
    test(count == 3);
    
    [s updateValue:v3];
    test(latest == v3);
    test(count == 4);
}
-(void) testObservableReentrantAdd {
    ObservableValueController* s = [ObservableValueController observableValueControllerWithInitialValue:@""];
    ObservableValue* t = s;
    NSMutableArray* a = [NSMutableArray array];
    TOCCancelTokenSource* c = [TOCCancelTokenSource new];
    
    __block void(^registerSelf)() = nil;
    void(^registerSelf_builder)() = ^{
        __block bool first = true;
        [t watchLatestValueOnArbitraryThread:^(id value) {
            if (!first) registerSelf();
            first = false;
            [a addObject:value];
        } untilCancelled:c.token];
    };
    registerSelf = [registerSelf_builder copy];
    registerSelf();
    
    // adding during a callback counts as adding after the callback
    // so we should see a doubling each time
    test([a isEqualToArray:@[@""]]);
    [s updateValue:@1];
    test([a isEqualToArray:(@[@"", @1, @1])]);
    [s updateValue:@2];
    test([a isEqualToArray:(@[@"", @1, @1, @2, @2, @2, @2])]);
    [s updateValue:@3];
    test([a isEqualToArray:(@[@"", @1, @1, @2, @2, @2, @2, @3, @3, @3, @3, @3, @3, @3, @3])]);
}
-(void) testObservableReentrantRemove {
    ObservableValueController* s = [ObservableValueController observableValueControllerWithInitialValue:@""];
    ObservableValue* t = s;
    NSMutableArray* a = [NSMutableArray array];
    TOCCancelTokenSource* c = [TOCCancelTokenSource new];
    
    for (int i = 0; i < 3; i++) {
        __block bool first = true;
        [t watchLatestValueOnArbitraryThread:^(id value) {
            if (!first) {
                [c cancel];
                [a addObject:value];
            }
            first = false;
        } untilCancelled:c.token];
    }
    
    // removing during a callback counts as removing after the callback
    // so we should see all the callbacks run, then they're all cancelled
    test([a isEqualToArray:(@[])]);
    [s updateValue:@1];
    test([a isEqualToArray:(@[@1, @1, @1])]);
    [s updateValue:@2];
    test([a isEqualToArray:(@[@1, @1, @1])]);
}

@end
