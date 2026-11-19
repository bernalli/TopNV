#import "SystemDarkMenuBar.h"
#import <dlfcn.h>
#import <objc/runtime.h>

// The installed framework's Swift interface takes Bool and an (Error?) -> Void reply.
@protocol DarkMenuBarManager
- (void)setUseFullScreenAppearanceOnUserSpace:(BOOL)enabled
                            completionHandler:(void (^)(NSError *))handler;
@end

@implementation SystemDarkMenuBarClient {
    id<DarkMenuBarManager> _manager;
}

+ (instancetype)resolve {
    static void *framework;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        framework = dlopen("/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore",
                           RTLD_LAZY | RTLD_LOCAL);
    });
    if (!framework) return nil;
    @try {
        Class cls = NSClassFromString(@"MBMenuBarItemManager");
        SEL setter = @selector(setUseFullScreenAppearanceOnUserSpace:completionHandler:);
        NSMethodSignature *sig = [cls instanceMethodSignatureForSelector:setter];
        if (sig.numberOfArguments != 4 || strcmp(sig.methodReturnType, @encode(void)) ||
            strcmp([sig getArgumentTypeAtIndex:2], @encode(BOOL)) ||
            strcmp([sig getArgumentTypeAtIndex:3], "@?")) return nil;
        id manager = [[cls alloc] init];
        if (![manager respondsToSelector:setter]) return nil;
        SystemDarkMenuBarClient *client = [[self alloc] init];
        client->_manager = manager;
        return client;
    } @catch (NSException *exception) {
        return nil;
    }
}

- (void)request:(BOOL)enabled completion:(void (^)(NSString *))completion {
    @try {
        [_manager setUseFullScreenAppearanceOnUserSpace:enabled completionHandler:^(NSError *error) {
            completion(error.description);
        }];
    } @catch (NSException *exception) {
        completion(exception.reason ?: exception.name);
    }
}
@end
