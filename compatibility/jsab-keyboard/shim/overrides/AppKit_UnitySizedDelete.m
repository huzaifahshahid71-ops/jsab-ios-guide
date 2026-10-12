// Opt-in compatibility experiment: old Unity overrides unsized new/delete, while
// newer libc++ string growth calls sized delete. Never send a system allocation
// into Unity's allocator. The converter excludes this file unless requested.
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <malloc/malloc.h>
#import <mach-o/dyld.h>
#import <stdatomic.h>
#import <unistd.h>

typedef void (*ShimDelete)(void *);
static _Atomic(ShimDelete) UnityDelete;
static atomic_flag Logged = ATOMIC_FLAG_INIT;

__attribute__((constructor)) static void ShimFindUnityDelete(void) {
    // NSBundle paths are translated by the AppKit shim. Use the loader's actual
    // image path instead of appending another Mac/Contents prefix.
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *path = _dyld_get_image_name(i);
        if (path && strstr(path, "/UnityPlayer.dylib")) {
            void *handle = dlopen(path, RTLD_LAZY | RTLD_FIRST);
            if (handle) UnityDelete = (ShimDelete)dlsym(handle, "_ZdlPv");
            break;
        }
    }
    NSLog(@"SHIM Unity sized-delete bridge: %@", UnityDelete ? @"ready" : @"Unity delete unavailable");
}

__attribute__((visibility("default")))
void ShimUnitySizedDelete(void *pointer, size_t size);
void ShimUnitySizedDelete(void *pointer, size_t size) {
    (void)size;
    if (!pointer) return;
    malloc_zone_t *zone = malloc_zone_from_ptr(pointer);
    if (zone) {
        malloc_zone_free(zone, pointer);
        return;
    }
    ShimDelete unityDelete = atomic_load(&UnityDelete);
    if (!unityDelete) {
        // Interposition can run before library constructors. Resolve lazily too.
        ShimDelete candidate = (ShimDelete)dlsym(RTLD_DEFAULT, "_ZdlPv");
        Dl_info owner = {0};
        if (candidate && dladdr((const void *)candidate, &owner) &&
            owner.dli_fname && strstr(owner.dli_fname, "/UnityPlayer.dylib")) {
            unityDelete = candidate;
            atomic_store(&UnityDelete, candidate);
        }
    }
    if (unityDelete) {
        if (!atomic_flag_test_and_set(&Logged))
            NSLog(@"SHIM sized delete: non-system allocation routed to Unity");
        unityDelete(pointer);
        return;
    }
    // Fail visibly instead of silently leaking or freeing through the wrong heap.
    static const char message[] = "SHIM sized delete: unknown allocation without Unity delete\n";
    write(STDERR_FILENO, message, sizeof(message) - 1);
    abort();
}

// Exporting a matching symbol alone does not redirect shared-cache libc++ calls.
// Request loader interposition explicitly; verify its use on the device.
extern void ShimSystemSizedDelete(void *, size_t) __asm__("__ZdlPvm");
__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement; const void *original; } SizedDeleteInterpose = {
    (const void *)ShimUnitySizedDelete, (const void *)ShimSystemSizedDelete
};

// Separate LiveContainer experiment. Do not change the normal signed launch.
// Resolve the legacy SPI at runtime: recent dyld versions may omit it entirely.
__attribute__((constructor)) static void ShimCheckLateInterposition(void) {
    if (![[NSBundle mainBundle] objectForInfoDictionaryKey:@"JSBLateAllocatorBridge"]) return;
    typedef void (*LateInterpose)(const struct mach_header *, const void *, size_t);
    LateInterpose interpose = (LateInterpose)dlsym(RTLD_DEFAULT, "dyld_dynamic_interpose");
    Dl_info cpp = {0};
    void *sizedDelete = dlsym(RTLD_DEFAULT, "_ZdlPvm");
    if (sizedDelete) dladdr(sizedDelete, &cpp);
    NSString *status = [NSString stringWithFormat:
        @"late API=%p; sized delete image=%s; Unity delete=%p\n",
        interpose, cpp.dli_fname ?: "unknown", atomic_load(&UnityDelete)];
    const struct mach_header *caller = NULL;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (name && strstr(name, "/libc++.1.dylib")) {
            caller = _dyld_get_image_header(i);
            break;
        }
    }
    if (interpose && caller && UnityDelete) {
        // The API changes bindings in the caller, not the delete provider.
        interpose(caller, &SizedDeleteInterpose, 1);
        status = [status stringByAppendingString:@"late interposition requested for libc++.1\n"];
    } else {
        status = [status stringByAppendingString:@"late interposition unavailable; no runtime patch applied\n"];
    }
    NSLog(@"SHIM LC allocator diagnostic: %@", status);
    NSURL *documents = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
        inDomains:NSUserDomainMask].firstObject;
    [status writeToURL:[documents URLByAppendingPathComponent:@"JSAB-allocator-diagnostic.txt"]
        atomically:YES encoding:NSUTF8StringEncoding error:nil];
}
