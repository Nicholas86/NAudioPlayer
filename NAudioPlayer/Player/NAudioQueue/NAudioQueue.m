//
//  NAudioQueue.m
//  NAudioPlayer
//
//  Created by 泽娄 on 2019/9/22.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import "NAudioQueue.h"
#import "NAudioSession.h"

#define kNumberOfBuffers 3              //AudioQueueBuffer数量，一般指明为3
#define kAQBufSize 128 * 1024        //每个AudioQueueBuffer的大小 128 * 1024

#define Size_DefaultBufferSize 10 * 2048 // 默认缓冲区大小

#define KNum_Descs 512 //复用的包描述数量

@interface NAudioQueue ()
{
    AudioQueueBufferRef audioQueueBuffer[kNumberOfBuffers];
    NSLock *_lock; /// 锁
    BOOL inUsed[kNumberOfBuffers];//标记当前buffer是否正在被使用
    UInt32 currBufferIndex;//当前使用的buffer的索引
    UInt32 currBufferFillOffset;//当前buffer已填充的数据量
    UInt32 currBufferPacketCount;//当前是第几个packet,  当前填充了多少帧
    AudioStreamPacketDescription audioStreamPacketDesc[KNum_Descs];
    
    bool _started;
}

/// 该属性指明了音频数据的格式信息，返回的数据是一个AudioStreamBasicDescription结构
@property (nonatomic, assign, readwrite) AudioStreamBasicDescription audioStreamBasicDescription;

@property (nonatomic, assign, readwrite) AudioQueueRef audioQueue; /// audio queue实例

@end

@implementation NAudioQueue

- (instancetype)initWithFilePath:(NSString *)filePath
{
    self = [super init];
    if (self) {
        
    }return self;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [self createAudioSession];
    }return self;
}

/// 音频文件描述信息
- (instancetype)initWithAudioDesc:(AudioStreamBasicDescription)audioDesc
{
    self = [super init];
    if (self) {
        _started = NO;
        currBufferIndex = 0;
        currBufferFillOffset = 0;
        currBufferPacketCount = 0;
        self.audioStreamBasicDescription = audioDesc;
//        [self createAudioSession];
        [self createAudioQueue];
    }return self;
}

- (void)createAudioSession
{
    [[NAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback]; /// 只支持音频播放
//    [[NAudioSession sharedInstance] setPreferredSampleRate:44100];
    [[NAudioSession sharedInstance] setActive:YES];
    [[NAudioSession sharedInstance] addRouteChangeListener];
}

/*
 参数及返回说明如下：
 1. inFormat：该参数指明了即将播放的音频的数据格式
 2. inCallbackProc：该回调用于当AudioQueue已使用完一个缓冲区时通知用户，用户可以继续填充音频数据
 3. inUserData：由用户传入的数据指针，用于传递给回调函数
 4. inCallbackRunLoop：指明回调事件发生在哪个RunLoop之中，如果传递NULL，表示在AudioQueue所在的线程上执行该回调事件，一般情况下，传递NULL即可。
 5. inCallbackRunLoopMode：指明回调事件发生的RunLoop的模式，传递NULL相当于kCFRunLoopCommonModes，通常情况下传递NULL即可
 6. outAQ：该AudioQueue的引用实例，
 */
- (void)createAudioQueue
{
    OSStatus status;
    status = AudioQueueNewOutput(&_audioStreamBasicDescription, NAudioQueueOutputCallback, (__bridge void * _Nullable)(self), CFRunLoopGetCurrent(), kCFRunLoopCommonModes, 0, &_audioQueue);
    
    if (status != noErr) {
        NSLog(@"AudioQueueNewOutput 失败");
    }
    
    NSLog(@"AudioQueueNewOutput 成功");

    // 设置音量
    AudioQueueSetParameter(_audioQueue, kAudioQueueParam_Volume, 1.0);
    
    [self createBuffer];
}

/*
 该方法的作用是为存放音频数据的缓冲区开辟空间

 参数及返回说明如下：
 1. inAQ：AudioQueue的引用实例
 2. inBufferByteSize：需要开辟的缓冲区的大小
 3. outBuffer：开辟的缓冲区的引用实例
 */
- (void)createBuffer
{
    OSStatus status;
    for (int i = 0; i < kNumberOfBuffers; i++) {
        status = AudioQueueAllocateBuffer(_audioQueue, kAQBufSize, &audioQueueBuffer[i]);
        inUsed[i] = NO; /// 默认都是未使用
        if (status != noErr) {
            NSLog(@"AudioQueueAllocateBuffer 失败!!!");
            continue;
        }
    }
    
    NSLog(@"AudioQueueAllocateBuffer 成功!!!");
}

/// 开始
- (void)start
{
    if (!_audioQueue) {
        NSLog(@"audioQueue is null!!!");
        return;
    }
    
    OSStatus status;
    /// 队列处理开始，此后系统开始自动调用回调(Callback)函数
    status = AudioQueueStart(_audioQueue, nil);
    
    if (status != noErr) {
        NSLog(@"AudioQueueStart 失败!!!");
    }
    
    NSLog(@"AudioQueueStart 成功!!!");
    
    /// 标记start始成功
    _started = YES;
}

/// 暂停
- (void)pause
{
    if (!_audioQueue) {
        NSLog(@"audioQueue is null!!!");
        return;
    }
    
    OSStatus status= AudioQueuePause(_audioQueue);
    if (status!= noErr){
//        [self.audioProperty error:LLYAudioError_AQ_PauseFail];
        return;
    }
}

/// 停止
- (void)stop
{
    if (!_audioQueue) {
        NSLog(@"audioQueue is null!!!");
        return;
    }

    if (_audioQueue) {
        OSStatus status= AudioQueueStop(_audioQueue, true);
        if (status!= noErr){
//            [self.audioProperty error:LLYAudioError_AQ_StopFail];
            return;
        }
    }
}

- (void)playData:(NSData *)data
 inNumberPackets:(UInt32)inNumberPackets
packetDescriptions:(AudioStreamPacketDescription *)packetDescriptions
           isEof:(BOOL)isEof
{
    
    if (packetDescriptions == NULL) {
        NSLog(@"packetDescriptions is null");
    }
    
    NSLog(@"data length: %lu", [data length]); /// 2048

    for (int i = 0; i < inNumberPackets; ++i) {
        /// 获取 AudioStreamPacketDescription对象
        AudioStreamPacketDescription packetDesc = packetDescriptions[i];
        SInt64 mStartOffset = packetDesc.mStartOffset;
        UInt32 mDataByteSize = packetDesc.mDataByteSize;
            
        /// 当前已填充数据大小 +将要填充的数据大小
        UInt32 totalByteSize = currBufferFillOffset + mDataByteSize;
        
        NSLog(@"currBufferFillOffset: %u, mDataByteSize: %u, totalByteSize: %u, Size_DefaultBufferSize: %u", (unsigned int)currBufferFillOffset, (unsigned int)mDataByteSize, totalByteSize, Size_DefaultBufferSize);

        if (totalByteSize >= Size_DefaultBufferSize) { /// 默认缓冲区播放标准大小
            ///  NSLog(@"当前buffer_%u已经满了，送给audioqueue去播吧",(unsigned int)currBufferIndex);
            /// 去播放
            
            inUsed[currBufferIndex] = YES;

            OSStatus status = AudioQueueEnqueueBuffer(_audioQueue, audioQueueBuffer[currBufferIndex], (UInt32)currBufferPacketCount, audioStreamPacketDesc);

            if (status == noErr) {
        
                if (!_started) {
                    
                    if (!_audioQueue) {
                        NSLog(@"audioQueue is null!!!");
                        return;
                    }
                    
                    OSStatus _error =  AudioQueueStart(_audioQueue, NULL);
                    
                    if (_error != noErr) {
                        NSLog(@"play failed, _error: %d", _error);
                    }
                    _started = YES;
                }
                
                currBufferIndex = (++currBufferIndex) % kNumberOfBuffers;
                currBufferFillOffset = 0;
                currBufferPacketCount = 0;
                
                while (inUsed[currBufferIndex]);
            }
            
            NSLog(@"给当前buffer_%u填装数据中",(unsigned int)currBufferIndex);
        }
    
        
        /// 取出当前AudioQueueBufferRef
        AudioQueueBufferRef currentFillBuffer = audioQueueBuffer[currBufferIndex];
        memcpy(currentFillBuffer->mAudioData + currBufferFillOffset, data.bytes + mStartOffset, mDataByteSize);
        
        currentFillBuffer->mAudioDataByteSize = (UInt32)(currBufferFillOffset + mDataByteSize);
        
        audioStreamPacketDesc[currBufferPacketCount] = packetDescriptions[i];
        audioStreamPacketDesc[currBufferPacketCount].mStartOffset = currBufferFillOffset;
        currBufferPacketCount += 1;

        currBufferFillOffset += mDataByteSize;
    }
}

- (void)p_putBufferToQueue
{
    inUsed[currBufferIndex] = YES;
    
    AudioQueueBufferRef outBufferRef = audioQueueBuffer[currBufferIndex];
    
    OSStatus error;

    if (currBufferPacketCount > 0) {
        NSLog(@"currBufferPacketCount > 0 ");
        error = AudioQueueEnqueueBuffer(_audioQueue, outBufferRef, currBufferPacketCount, audioStreamPacketDesc);
    }else{
        NSLog(@"currBufferPacketCount <= 0 ");

        error = AudioQueueEnqueueBuffer(_audioQueue, outBufferRef, 0, NULL);
    }
    
    if (error != noErr) {
        /// [_audioProperty error:LLYAudioError_AQB_EnqueueFail];
        return;
    }
    
//    if (_audioProperty.status != LLYAudioStatus_Playing) {
//        _audioProperty.status = LLYAudioStatus_Playing;
//    }
    
    if (!_started) {
        [self start];
    }
    
    /// [self start];
    
    currBufferIndex = ++currBufferIndex % kNumberOfBuffers;
    
    NSLog(@"currBufferIndex: %u", (unsigned int)currBufferIndex);
    
    currBufferPacketCount = 0;
    
    /// 当前buffer已填充的数据量恢复为0
    currBufferFillOffset = 0;
    
    /// while (inUsed[currBufferIndex]);
    while (inUsed[currBufferIndex]) {
        /// NSLog(@"一直循环");
    }
}

#pragma mark private method

- (void)p_audioQueueOutput:(AudioQueueRef)inAQ inBuffer:(AudioQueueBufferRef)inBuffer
{
    for (int i = 0; i < kNumberOfBuffers; i++) {
        
        if (inBuffer == audioQueueBuffer[i]) {
            [_lock lock];
            /// // 将这个 buffer 设为未使用
            inUsed[i] = NO;
            NSLog(@"当前buffer_%d的数据已经播放完了 还给程序继续装数据去吧！！！！！！",i);
            [_lock unlock];
        }
    }
}

/*
    该回调用于当AudioQueue已使用完一个缓冲区时通知用户，用户能够继续填充音频数据
 */
static void NAudioQueueOutputCallback(void *inUserData, AudioQueueRef inAQ,
                                        AudioQueueBufferRef buffer){
        
    NAudioQueue *_audioQueue = (__bridge NAudioQueue *)inUserData;
    
    // OSStatus status;
    
//    NSLog(@"audioQueue 回调");
    
    [_audioQueue p_audioQueueOutput:inAQ inBuffer:buffer];
    
    /*
    /// 读取包数据
    UInt32 numBytes = buffer->mAudioDataBytesCapacity;
    UInt32 numPackets = _audioQueue->numPacketsToRead;
    
    status = AudioFileReadPacketData(_audioQueue->audioFileID, NO, &numBytes, _audioQueue->packetDescs, _audioQueue->packetIndex,&numPackets, buffer->mAudioData);
    
    if (status != noErr) {
        NSLog(@"AudioFileReadPackets 失败");
        return;
    }
    
    NSLog(@"读取包数据, status: %d", status);
    
    //成功读取时
    if (numPackets>0) {
        //将缓冲的容量设置为与读取的音频数据一样大小(确保内存空间)
        buffer->mAudioDataByteSize = numBytes;
        //完成给队列配置缓存的处理
        status = AudioQueueEnqueueBuffer(_audioQueue->audioQueue, buffer, numPackets, _audioQueue->packetDescs);
        //移动包的位置
        _audioQueue->packetIndex += numPackets;
        
        /// 标识播放状态
        _audioQueue.playing = YES;
    }
     */
}

@end
