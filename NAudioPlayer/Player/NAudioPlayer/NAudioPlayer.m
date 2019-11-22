//
//  NAudioPlayer.m
//  NAudioPlayer
//
//  Created by 泽娄 on 2019/9/22.
//  Copyright © 2019 泽娄. All rights reserved.
//

#import "NAudioPlayer.h"
#import "NAudioFileStream.h"
#import "NAudioQueue.h"
#import "NAudioBuffer.h"
#import "NAudioSession.h"

#define kAudioFileBufferSize 5120   //文件读取数据的缓冲区大小

@interface NAudioPlayer ()<NAudioFileStreamDelegate>{
    NAudioBuffer *_buffer;
    NSThread *_thread;
    NSTimer *_timer;
    
    BOOL _isFileStreamExisted;
    unsigned long long  _fileLength;        // Length of the file in bytes
    
//    BOOL _started;
    BOOL _pauseRequired;
    NSTimeInterval _timingOffset;
    
    double _seekTime;
    BOOL _seekWasRequested; /// 标记seek
}

@property (nonatomic, readwrite) NAudioPlayerStatus status;

@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, strong) NAudioFileStream *audioFileStream;
@property (nonatomic, strong) NAudioQueue *audioQueue;

@property (nonatomic, strong) NSFileHandle *audioFileHandle;
@property (nonatomic, strong) NSData *audioFileData; // 每次读取到的文件数据
@end

@implementation NAudioPlayer

- (instancetype)initWithFilePath:(NSString *)filePath
{
    self = [super init];
    if (self) {
        _status = NAudioPlayerStatusStopped;
        _isFileStreamExisted = NO;
//        _started = NO;
        _pauseRequired = NO;
        _seekWasRequested = NO;
        _filePath = filePath;
        _audioFileHandle = [NSFileHandle fileHandleForReadingAtPath:filePath];
        _fileLength = [[[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil] fileSize];
        NSLog(@"文件总长度, NAudioPlayer, _fileLength: %llu", _fileLength);
    }return self;
}

/// 解析文件
- (void)createAudioFileStream
{
    _audioFileStream = [[NAudioFileStream alloc] initWithFilePath:_filePath fileLength:_fileLength];
    _audioFileStream.delegate = self;
}

- (void)play
{
//    if (!_started) {
//        _started = YES;
//        _thread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMain) object:nil];
//        [_thread start];
//    }else{
//        if (self.status == NAudioPlayerStatusPaused || _pauseRequired) {
//            _pauseRequired = NO;
//            [_audioQueue start];
//        }
//    }
    if (self.status == NAudioPlayerStatusStopped) {
//        _started = YES;
        /// 更新播放状态: 等待播放
        [self setStatusInternal:(NAudioPlayerStatusWaiting)];
        _thread = [[NSThread alloc] initWithTarget:self selector:@selector(threadMain) object:nil];
        [_thread start];
    }else if (self.status == NAudioPlayerStatusPaused){
        /// 更新播放状态: 等待播放
        [self setStatusInternal:(NAudioPlayerStatusWaiting)];
        [_audioQueue start];
    }
}

- (void)pause
{
    if (!_audioQueue) {
        NSLog(@"_audioQueue is null");
        return;
    }
    
    if (self.status == NAudioPlayerStatusWaiting || self.status == NAudioPlayerStatusPlaying) {
        NSLog(@"暂停播放");
        /// 更新播放状态: NAudioPlayerStatusPaused
        [self setStatusInternal:NAudioPlayerStatusPaused];
        [self.audioQueue pause];
        // _pauseRequired = YES;
    }
}

- (void)stop
{
    if (!_audioQueue) {
        NSLog(@"_audioQueue is null");
        return;
    }
    
    if (self.status == NAudioPlayerStatusWaiting || self.status == NAudioPlayerStatusPlaying) {
        NSLog(@"停止播放");
        /// 更新播放状态: NAudioPlayerStatusPaused
        [self setStatusInternal:NAudioPlayerStatusStopped];
        [self.audioQueue stop];
    }
}

- (void)playWithUrlString:(NSString *)urlString
{
    if (_audioFileStream) {
        self.audioFileStream = nil;
        self.audioFileStream.delegate = nil;
    }
    
    if (_audioQueue) {
        self.audioQueue = nil;
    }
    
    /// 创建文件解析对象
    [self createAudioFileStream];
}

- (void)seekToTime:(double)newTime
{
    @synchronized (self) {
        _seekWasRequested = YES;
    }
}

/*
 注意两点:
 1. 定时器时间间隔尽量小, 或者用do...while循环
 2. 定时器里面读取文件的长度, 大于内部buffer装的长度
 */
- (void)threadMain
{
//    /// 更新播放状态: 等待播放
//    [self setStatusInternal:(NAudioPlayerStatusWaiting)];
//    while ((self.status != NAudioPlayerStatusStopped) && _started) {
//        NSLog(@"do。。。");
//        /// 创建文件解析对象
//        if (!_audioFileStream) {
//           [self createAudioFileStream];
//        }
//
//        /// play
//        if (_started) {
//            [self handleTask];
//        }
//
//        /// pause
//
//    }
    
    do {
        NSLog(@"do。。。");
        /// 创建文件解析对象
        if (!_audioFileStream) {
           [self createAudioFileStream];
        }

//        /// pause
//        if (_pauseRequired) {
//            [self setStatusInternal:NAudioPlayerStatusPaused];
//            [self.audioQueue pause];
//            _pauseRequired = NO;
//        }
    
        /// NSLog(@"_audioQueue.buffersUsed: %ld", (long)_audioQueue.buffersUsed);
        
        /// seek
        if (_seekWasRequested) {
            
            _seekWasRequested = NO;
        }
        
        /// pause
        if (self.status == NAudioPlayerStatusPaused) {
            NSLog(@"for 循环 里 暂停播放");
            [self setStatusInternal:NAudioPlayerStatusStopped];
            [self.audioQueue pause];
//            _pauseRequired = NO;
        }
        
        /// play
        [self handleTask];
//        if (_started) {
//            [self handleTask];
//        }
    
//        if (_started) {
//            [self handleTask];
//        }

    } while (self.status != NAudioPlayerStatusStopped);

    return;
    
    /// 创建文件解析对象
    if (!_audioFileStream) {
        [self createAudioFileStream];
    }
    
    /// 子线程开启定时器
    if (@available(iOS 10.0, *)) { /// 时间间隔设置小
        _timer = [NSTimer scheduledTimerWithTimeInterval:0.1 repeats:YES block:^(NSTimer * _Nonnull timer) {
            [self handleTask];
        }];
    } else {
        // Fallback on earlier versions
    }
    [[NSRunLoop currentRunLoop] run];
}

/// 定时器
- (void)handleTask
{
    NSLog(@"定时器循环");
//    /// 更新播放状态: 等待播放
//    [self setStatusInternal:(NAudioPlayerStatusWaiting)];

    if (self.status == NAudioPlayerStatusWaiting || self.status == NAudioPlayerStatusPlaying) {
        /// 外部读的数据比内部多
       NSData *data = [self.audioFileHandle readDataOfLength:kAudioFileBufferSize];
       [_audioFileStream parseData:data]; /// 解析数据
    }
}

#pragma mark NAudioFileStreamDelegate
/// 准备解析音频数据帧
- (void)audioStream_readyToProducePacketsWithAudioFileStream:(NAudioFileStream *)audioFileStream
{
    NSLog(@">>>>>>>>>>>> 准备解析音频数据帧 <<<<<<<<<<<<<<");
    /// 初始化audioQueue
    if (!_audioQueue) {
     _audioQueue = [[NAudioQueue alloc] initWithAudioDesc:audioFileStream.audioStreamBasicDescription audioFileStreamID:audioFileStream.audioFileStreamID];
    }
}

/// 解析音频数据帧并播放
- (void)audioStream_packetsWithAudioFileStream:(NAudioFileStream *)audioFileStream
                                          data:(NSData *)data
                                     inputData:(nonnull const void *)inputData
                                 inNumberBytes:(UInt32)inNumberBytes
                               inNumberPackets:(UInt32)inNumberPackets inPacketDescrrptions:(nonnull AudioStreamPacketDescription *)inPacketDescrrptions
{
    NSLog(@">>>>>>>>>>>> 解析音频数据帧(%ld)---- 开始播放 <<<<<<<<<<<<<<", [data length]);
    if (!_audioQueue) {
        NSLog(@"_audioQueue is null");
        return;
    }
    
    if (self.status == NAudioPlayerStatusWaiting || self.status == NAudioPlayerStatusPlaying) {
       /// 更新播放状态: NAudioPlayerStatusPlaying
        [self setStatusInternal:(NAudioPlayerStatusPlaying)];
        [_audioQueue playData:data inputData:inputData inNumberPackets:inNumberPackets packetDescriptions:inPacketDescrrptions isEof:YES];
    }
}

#pragma mark private method
- (void)setStatusInternal:(NAudioPlayerStatus)status
{
    if (_status == status)
    {
        return;
    }
    
    [self willChangeValueForKey:@"status"];
    _status = status;
    [self didChangeValueForKey:@"status"];
}

#pragma mark setter && getter
- (NSTimeInterval)duration
{
    if (!_audioFileStream) {
        return 0;
    }
    return [_audioFileStream duration];
}

- (UInt32)bitRate
{
    if (!_audioFileStream) {
        return 0;
    }
    return [_audioFileStream bitRate];
}

- (NSTimeInterval)progress
{
//    if (_seekRequired)
//    {
//        return _seekTime;
//    }
    return _timingOffset + _audioQueue.playedTime;
}

@end
