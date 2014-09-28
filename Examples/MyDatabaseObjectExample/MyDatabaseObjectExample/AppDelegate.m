#import "AppDelegate.h"

#import "MyDatabaseObject.h"
#import "Car.h"

@interface AppDelegate ()
@property (weak) IBOutlet NSWindow *window;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	Car *car = [[Car alloc] init];
	car.make = @"Tesla";
	car.model = @"Model S";
	
	[car makeImmutable];
	
	// Try me
	@try {
		car.make = @"Ford"; // Throws exception: Attempting to mutate immutable object...
	}
	@catch (NSException *exception) {
		NSLog(@"Threw exception: %@", exception);
	}
	
	NSLog(@"car.changedProperties = %@", car.changedProperties);
	
	[car clearChangedProperties];
	NSLog(@"car.changedProperties = %@", car.changedProperties);
}

@end
