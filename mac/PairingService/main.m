// This process is the stable Keychain client across updates to the main app.
#import <Foundation/Foundation.h>
#import <Security/Security.h>

@protocol ConduitPairingProtocol
- (void)read:(NSString *)address interactive:(BOOL)interactive reply:(void (^)(int32_t, NSData *))reply;
- (void)save:(NSData *)data address:(NSString *)address reply:(void (^)(int32_t))reply;
- (void)forget:(NSString *)address reply:(void (^)(int32_t))reply;
@end

@interface PairingService : NSObject <NSXPCListenerDelegate, ConduitPairingProtocol>
@end

@implementation PairingService
- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection {
    // The signed service bundle pins the host identity. Check every incoming message.
    NSString *requirement = [NSBundle.mainBundle objectForInfoDictionaryKey:@"ConduitHostRequirement"];
    if (!requirement.length) return NO;
    [connection setCodeSigningRequirement:requirement];
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(ConduitPairingProtocol)];
    connection.exportedObject = self;
    [connection resume];
    return YES;
}

static NSMutableDictionary *query(NSString *address) {
    return [@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
              (__bridge id)kSecAttrService: @"dev.conduit.bluetooth",
              (__bridge id)kSecAttrAccount: address} mutableCopy];
}
- (void)read:(NSString *)address interactive:(BOOL)interactive reply:(void (^)(int32_t, NSData *))reply {
    NSMutableDictionary *item = query(address);
    item[(__bridge id)kSecReturnData] = @YES;
    if (!interactive) item[(__bridge id)kSecUseAuthenticationUI] = (__bridge id)kSecUseAuthenticationUIFail;
    CFTypeRef value = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)item, &value);
    reply(status, CFBridgingRelease(value));
}
- (void)save:(NSData *)data address:(NSString *)address reply:(void (^)(int32_t))reply {
    if (data.length != 64) { reply(errSecParam); return; }
    NSMutableDictionary *item = query(address);
    NSDictionary *update = @{(__bridge id)kSecValueData: data};
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)item, (__bridge CFDictionaryRef)update);
    if (status == errSecItemNotFound) {
        [item addEntriesFromDictionary:update];
        item[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
        status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    }
    reply(status);
}
- (void)forget:(NSString *)address reply:(void (^)(int32_t))reply {
    reply(SecItemDelete((__bridge CFDictionaryRef)query(address)));
}
@end

int main(void) {
    @autoreleasepool {
        __attribute__((objc_precise_lifetime)) PairingService *service = [PairingService new];
        NSXPCListener *listener = [NSXPCListener serviceListener];
        listener.delegate = service;
        [listener resume];
    }
    return 0;
}
