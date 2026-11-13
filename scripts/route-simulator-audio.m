// CI-only bridge for Simulator.app's per-device audio menu. Not part of the app.
// Selector references: https://github.com/subdiox/SimKit/blob/74c895ea4b696ad51cf18f7204ab6fb79dde8915/Sources/Control/SimulatorAudio.swift
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <dispatch/dispatch.h>

@interface NSObject (SimulatorAudioCI)
+ (id)sharedServiceContextForDeveloperDir:(NSString *)path error:(NSError **)error;
- (id)defaultDeviceSetWithError:(NSError **)error;
- (id)initWithDevice:(id)device eventHandlerQueue:(dispatch_queue_t)queue error:(NSError **)error changedEventHandler:(void (^)(id))handler;
- (void)routeGuestWithScope:(NSInteger)scope to:(NSString *)uid completionQueue:(dispatch_queue_t)queue completionHandler:(void (^)(NSError *))handler;
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) return 2;
        NSString *developer = @(argv[1]);
        NSString *udid = @(argv[2]);
        if (!dlopen("/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator", RTLD_NOW | RTLD_GLOBAL) ||
            !dlopen([[developer stringByAppendingPathComponent:@"Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"] UTF8String], RTLD_NOW | RTLD_GLOBAL)) {
            fprintf(stderr, "Simulator framework load failed: %s\n", dlerror()); return 1;
        }
        NSError *error = nil;
        id context = [NSClassFromString(@"SimServiceContext") sharedServiceContextForDeveloperDir:developer error:&error];
        id set = [context defaultDeviceSetWithError:&error];
        id target = nil;
        for (id device in [set valueForKey:@"availableDevices"]) {
            if ([[[device valueForKey:@"UDID"] UUIDString] isEqualToString:udid]) { target = device; break; }
        }
        Class clientClass = NSClassFromString(@"_TtC12SimulatorKit20SimDeviceAudioClient");
        if (!target || !clientClass || error) { NSLog(@"Audio device resolution failed: %@", error); return 1; }
        id client = [[clientClass alloc] initWithDevice:target eventHandlerQueue:dispatch_get_main_queue()
                                                error:&error changedEventHandler:^(id event) {}];
        if (!client || error) { NSLog(@"Audio client failed: %@", error); return 1; }
        for (NSInteger scope = 0; scope < 2; scope++) {
            NSString *key = scope == 0 ? @"inputDevices" : @"outputDevices";
            id state = [client valueForKey:@"currentState"];
            NSString *uid = nil;
            for (id device in [state valueForKey:key]) {
                NSLog(@"Simulator %@ candidate: %@ (%@)", key, [device valueForKey:@"name"], [device valueForKey:@"UID"]);
                if ([[device valueForKey:@"name"] isEqualToString:@"BlackHole 2ch"]) uid = [device valueForKey:@"UID"];
            }
            if (!uid) { NSLog(@"BlackHole missing from simulator %@", key); return 1; }
            __block BOOL done = NO;
            __block NSError *routeError = nil;
            [client routeGuestWithScope:scope to:uid completionQueue:dispatch_get_main_queue() completionHandler:^(NSError *failure) {
                routeError = failure; done = YES;
            }];
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
            while (!done && [deadline timeIntervalSinceNow] > 0) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            }
            if (!done || routeError) { NSLog(@"Simulator audio route failed: %@", routeError); return 1; }
            NSLog(@"Simulator %@ explicitly routed to %@", key, uid);
        }
    }
    return 0;
}
