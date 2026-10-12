#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#include <dlfcn.h>
#include <string.h>

typedef struct { UInt32 selector, scope, element; } JSBAudioAddress;
static const OSStatus JSBUnknown = 2003332927;
static const UInt32 JSBOutputDevice = 2;
static NSString *JSBSelector(UInt32 x) {
    char c[5] = {(char)(x>>24),(char)(x>>16),(char)(x>>8),(char)x,0};
    return [NSString stringWithUTF8String:c] ?: @"?";
}
static UInt32 JSBSize(UInt32 selector, BOOL input) {
    switch (selector) {
        case 'dev#': case 'dOut': case 'dSys': case 'dIn ': case 'livn':
        case 'dflt': case 'fsiz': case 'ltnc': case 'saft': case 'stm#': return 4;
        case 'name': return sizeof("iPhone Stereo Output");
        case 'manu': return sizeof("Apple");
        case 'lnam': case 'uid ': case 'lmak': return sizeof(CFStringRef);
        case 'nsrt': return sizeof(Float64);
        case 'nsr#': case 'fsz#': return sizeof(AudioValueRange);
        case 'sfmt': return sizeof(AudioStreamBasicDescription);
        case 'srnd': return offsetof(AudioChannelLayout,mChannelDescriptions);
        case 'slay': return input ? offsetof(AudioBufferList,mBuffers) : sizeof(AudioBufferList);
        default: return 0;
    }
}
static OSStatus JSBRead(UInt32 selector, BOOL input, UInt32 *size, void *out) {
    UInt32 need = JSBSize(selector,input);
    if (!need) { NSLog(@"SHIM audio unknown property %@",JSBSelector(selector)); return JSBUnknown; }
    if (!size || !out || *size < need) return 'psiz';
    memset(out,0,need);
    switch (selector) {
        case 'dev#': case 'dOut': case 'dSys': *(UInt32 *)out = JSBOutputDevice; break;
        case 'dIn ': break;
        case 'livn': case 'dflt': *(UInt32 *)out = 1; break;
        case 'stm#': *(UInt32 *)out = input ? 0 : 3; break;
        case 'fsiz': *(UInt32 *)out = 512; break;
        case 'ltnc': case 'saft': break;
        case 'name': memcpy(out,"iPhone Stereo Output",need); break;
        case 'manu': memcpy(out,"Apple",need); break;
        case 'lnam': case 'uid ': case 'lmak': {
            CFStringRef value = selector=='uid ' ? CFSTR("jsab.iphone.output") : selector=='lmak' ? CFSTR("Apple") : CFSTR("iPhone Stereo Output");
            *(CFStringRef *)out = CFRetain(value);
            break;
        }
        case 'nsrt': *(Float64 *)out = AVAudioSession.sharedInstance.sampleRate ?: 48000; break;
        case 'nsr#': *(AudioValueRange *)out = (AudioValueRange){48000,48000}; break;
        case 'fsz#': *(AudioValueRange *)out = (AudioValueRange){128,4096}; break;
        case 'slay': {
            AudioBufferList *list = out;
            list->mNumberBuffers = input ? 0 : 1;
            if (!input) list->mBuffers[0].mNumberChannels = 2;
            break;
        }
        case 'srnd': ((AudioChannelLayout *)out)->mChannelLayoutTag=kAudioChannelLayoutTag_Stereo; break;
        case 'sfmt': {
            AudioStreamBasicDescription *format = out;
            *format = (AudioStreamBasicDescription){48000,kAudioFormatLinearPCM,kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,8,1,8,2,32,0};
            break;
        }
    }
    *size = need;
    NSLog(@"SHIM audio property %@ -> %u bytes",JSBSelector(selector),need);
    return noErr;
}
OSStatus AudioHardwareGetPropertyInfo(UInt32 selector, UInt32 *size, Boolean *writable) {
    UInt32 need = JSBSize(selector,NO);
    NSLog(@"SHIM audio hardware info %@ -> %u",JSBSelector(selector),need);
    if (!need) return JSBUnknown;
    if (size) *size=need;
    if (writable) *writable=NO;
    return noErr;
}
OSStatus AudioHardwareGetProperty(UInt32 selector,UInt32 *size,void *out) { return JSBRead(selector,NO,size,out); }
OSStatus AudioHardwareAddPropertyListener(UInt32 selector,void *listener,void *context) { return noErr; }
OSStatus AudioDeviceGetPropertyInfo(UInt32 device,UInt32 channel,Boolean input,UInt32 selector,UInt32 *size,Boolean *writable) {
    UInt32 need=JSBSize(selector,input);
    NSLog(@"SHIM audio device info %@ input=%u -> %u",JSBSelector(selector),input,need);
    if (!need) return JSBUnknown;
    if (size) *size=need;
    if (writable) *writable=selector=='fsiz'||selector=='nsrt';
    return noErr;
}
OSStatus AudioDeviceGetProperty(UInt32 device,UInt32 channel,Boolean input,UInt32 selector,UInt32 *size,void *out) { return JSBRead(selector,input,size,out); }
OSStatus AudioDeviceSetProperty(UInt32 device,const AudioTimeStamp *time,UInt32 channel,Boolean input,UInt32 selector,UInt32 size,const void *data) {
    NSLog(@"SHIM audio device set %@",JSBSelector(selector));
    return selector=='fsiz'||selector=='nsrt' ? noErr : JSBUnknown;
}
OSStatus AudioObjectGetPropertyDataSize(UInt32 object,const JSBAudioAddress *a,UInt32 qualifierSize,const void *qualifier,UInt32 *out) {
    UInt32 need=JSBSize(a->selector,a->scope=='inpt');
    if (!need) { NSLog(@"SHIM audio object size unknown %@",JSBSelector(a->selector)); return JSBUnknown; }
    if (out) *out=need;
    return noErr;
}
OSStatus AudioObjectGetPropertyData(UInt32 object,const JSBAudioAddress *a,UInt32 qualifierSize,const void *qualifier,UInt32 *size,void *out) { return JSBRead(a->selector,a->scope=='inpt',size,out); }

AudioComponent AudioComponentFindNext(AudioComponent previous,const AudioComponentDescription *description) {
    typedef AudioComponent (*Fn)(AudioComponent,const AudioComponentDescription *);
    static Fn original;
    if (!original) original=(Fn)dlsym(dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox",RTLD_NOW),"AudioComponentFindNext");
    AudioComponentDescription mapped=*description;
    if (mapped.componentType==kAudioUnitType_Output && (mapped.componentSubType=='ahal'||mapped.componentSubType=='def '||mapped.componentSubType=='sys ')) {
        mapped.componentSubType=kAudioUnitSubType_RemoteIO;
        NSLog(@"SHIM Mac audio output -> RemoteIO");
    }
    return original ? original(previous,&mapped) : NULL;
}
OSStatus AudioUnitSetProperty(AudioUnit unit,AudioUnitPropertyID property,AudioUnitScope scope,AudioUnitElement element,const void *data,UInt32 size) {
    typedef OSStatus (*Fn)(AudioUnit,AudioUnitPropertyID,AudioUnitScope,AudioUnitElement,const void *,UInt32);
    static Fn original;
    if (property==2000) { NSLog(@"SHIM RemoteIO uses current iPhone output route"); return noErr; }
    if (!original) original=(Fn)dlsym(dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox",RTLD_NOW),"AudioUnitSetProperty");
    AudioStreamBasicDescription correctedFormat;
    if (property==kAudioUnitProperty_StreamFormat && size>=sizeof(AudioStreamBasicDescription)) {
        correctedFormat=*(const AudioStreamBasicDescription *)data;
        if (!(correctedFormat.mSampleRate>0)) correctedFormat.mSampleRate=AVAudioSession.sharedInstance.sampleRate ?: 48000;
        data=&correctedFormat;
        const AudioStreamBasicDescription *f=data;
        NSLog(@"SHIM audio format rate=%.0f channels=%u bytes/frame=%u flags=%u",f->mSampleRate,f->mChannelsPerFrame,f->mBytesPerFrame,f->mFormatFlags);
    }
    if (property==kAudioUnitProperty_MaximumFramesPerSlice && size>=4) NSLog(@"SHIM audio maximum frames %u",*(const UInt32 *)data);
    OSStatus result=original?original(unit,property,scope,element,data,size):-1;
    NSLog(@"SHIM audio unit set %u scope=%u element=%u -> %d",property,scope,element,result);
    return result;
}
OSStatus AudioUnitGetProperty(AudioUnit unit,AudioUnitPropertyID property,AudioUnitScope scope,AudioUnitElement element,void *data,UInt32 *size) {
    typedef OSStatus (*Fn)(AudioUnit,AudioUnitPropertyID,AudioUnitScope,AudioUnitElement,void *,UInt32 *);
    static Fn original;
    if (!original) original=(Fn)dlsym(dlopen("/System/Library/Frameworks/AudioToolbox.framework/AudioToolbox",RTLD_NOW),"AudioUnitGetProperty");
    OSStatus r=original?original(unit,property,scope,element,data,size):-1;
    NSLog(@"SHIM audio unit get %u scope=%u element=%u bytes=%u -> %d",property,scope,element,size?*size:0,r);
    if (!r && property==8 && size && *size>=sizeof(AudioStreamBasicDescription)) {
        AudioStreamBasicDescription *f=data;
        if (!(f->mSampleRate>0)) f->mSampleRate=AVAudioSession.sharedInstance.sampleRate ?: 48000;
        NSLog(@"SHIM audio queried format rate=%.0f channels=%u bytes/frame=%u",f->mSampleRate,f->mChannelsPerFrame,f->mBytesPerFrame);
    }
    return r;
}
__attribute__((constructor)) static void JSBActivateAudio(void) {
    @autoreleasepool {
        NSError *error=nil;
        AVAudioSession *session=AVAudioSession.sharedInstance;
        [session setCategory:AVAudioSessionCategoryPlayback error:&error];
        [session setActive:YES error:&error];
        NSLog(@"SHIM iPhone audio session rate=%.0f channels=%lu error=%@",session.sampleRate,(unsigned long)session.outputNumberOfChannels,error);
    }
}
