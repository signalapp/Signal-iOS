#import "AppDelegate.h"

#import "MyDatabaseObject.h"
#import "Car.h"

@interface AppDelegate ()
@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate
{
	Car *car;
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	car = [[Car alloc] init];
	car.make = @"Tesla";
	car.model = @"Model S";
	
	[self demoMakeImmutable];
	[self demoChangedProperties];
}

- (void)demoMakeImmutable
{
	[car makeImmutable];
	
	// Try me
	@try {
		car.make = @"Ford"; // Throws exception: Attempting to mutate immutable object...
	}
	@catch (NSException *exception) {
		NSLog(@"Threw exception: %@", exception);
	}
}

- (void)demoChangedProperties
{
	if (car.isImmutable) {
		car = [car copy]; // make mutable copy
	}
	
	[car clearChangedProperties];
	NSLog(@"car.changedProperties = %@", car.changedProperties);
	
	car.model = @"Model X";
	NSLog(@"car.changedProperties = %@", car.changedProperties);
	
	[car clearChangedProperties];
	NSLog(@"car.changedProperties = %@", car.changedProperties);
}

@end
