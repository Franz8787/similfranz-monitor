// similFranz Pocket — avvio dell'app e comandi di verifica via URL (simulafranz-pocket://...).
#import "AppDelegate.h"
#import "CtlModel.h"
#import "PkViewController.h"
#import "SFLog.h"

@implementation AppDelegate { CtlModel *_model; PkViewController *_vc; }

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    SFLog(@"avvio similFranz Pocket %@", [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]);
    application.idleTimerDisabled = YES;             // lo schermo resta acceso durante lo scenario
    _model = [CtlModel new];
    _vc = [[PkViewController alloc] initWithModel:_model];
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor blackColor];
    self.window.tintColor = [UIColor colorWithRed:0.04 green:0.52 blue:1 alpha:1];
    self.window.rootViewController = _vc;
    [self.window makeKeyAndVisible];
    [_model start];
    return YES;
}
- (void)applicationDidEnterBackground:(UIApplication *)application { [_model suspend]; }
- (void)applicationDidBecomeActive:(UIApplication *)application { application.idleTimerDisabled = YES; [_model start]; }

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url sourceApplication:(NSString *)src annotation:(id)ann {
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    for (NSString *kv in [url.query componentsSeparatedByString:@"&"]) {
        NSRange r = [kv rangeOfString:@"="];
        if (r.location != NSNotFound) q[[kv substringToIndex:r.location]] = [[kv substringFromIndex:r.location + 1] stringByRemovingPercentEncoding] ?: @"";
    }
    if (url.host.length) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self->_vc debug:url.host query:q]; });
    return YES;
}
@end
