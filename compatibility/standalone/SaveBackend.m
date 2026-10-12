#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdbool.h>
#include <string.h>

static void JSBCheckLocalStorage(void) {
    void *library=NULL;
    for (uint32_t i=0;i<_dyld_image_count();i++) {
        const char *name=_dyld_get_image_name(i);
        if (name && strstr(name,"libsteam_api.dylib")) {
            library=dlopen(name,RTLD_NOW);
            break;
        }
    }
    typedef void *(*StorageFn)(void);
    typedef bool (*ExistsFn)(void *,const char *);
    typedef bool (*WriteFn)(void *,const char *,const void *,int32_t);
    typedef int32_t (*ReadFn)(void *,const char *,void *,int32_t);
    typedef bool (*DeleteFn)(void *,const char *);
    StorageFn get=library?(StorageFn)dlsym(library,"SteamAPI_SteamRemoteStorage_v016"):NULL;
    ExistsFn exists=library?(ExistsFn)dlsym(library,"SteamAPI_ISteamRemoteStorage_FileExists"):NULL;
    WriteFn write=library?(WriteFn)dlsym(library,"SteamAPI_ISteamRemoteStorage_FileWrite"):NULL;
    ReadFn read=library?(ReadFn)dlsym(library,"SteamAPI_ISteamRemoteStorage_FileRead"):NULL;
    DeleteFn remove=library?(DeleteFn)dlsym(library,"SteamAPI_ISteamRemoteStorage_FileDelete"):NULL;
    if (!get||!exists||!write||!read||!remove) { NSLog(@"SHIM local save probe unavailable"); return; }
    void *storage=get();
    if (!storage) { NSLog(@"SHIM local save interface unavailable"); return; }
    const char *file=".jsabcompat-storage-probe";
    const char payload[]="JSAB iPhone local storage probe v1";
    bool previous=exists(storage,file);
    char buffer[sizeof(payload)]={0};
    bool success;
    if (previous) {
        success=read(storage,file,buffer,sizeof(buffer))==sizeof(payload)&&memcmp(buffer,payload,sizeof(payload))==0;
        if (success) remove(storage,file);
    } else {
        success=write(storage,file,payload,sizeof(payload))&&read(storage,file,buffer,sizeof(buffer))==sizeof(payload)&&memcmp(buffer,payload,sizeof(payload))==0;
    }
    NSLog(@"SHIM local save %@ verification: %@",previous?@"restart":@"write/read",success?@"PASS":@"FAIL");
    dlclose(library);
}
__attribute__((constructor)) static void JSBConfigureLocalStorage(void) {
    @autoreleasepool {
        NSString *directory=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/JSABLocal"];
        NSError *error=nil;
        BOOL ready=[NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error];
        if (ready && !getenv("XDG_DATA_HOME")) setenv("XDG_DATA_HOME",directory.fileSystemRepresentation,1);
        NSLog(@"SHIM local save directory %@ ready=%d error=%@",directory,ready,error);
    }
#ifdef JSB_SAVE_DIAGNOSTIC
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{ JSBCheckLocalStorage(); });
#endif
}
