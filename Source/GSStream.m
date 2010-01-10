/** Implementation for GSStream for GNUStep
   Copyright (C) 2006 Free Software Foundation, Inc.

   Written by:  Derek Zhou <derekzhou@gmail.com>
   Written by:  Richard Frith-Macdonald <rfm@gnu.org>
   Date: 2006

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.

   */

#include "config.h"

#import <Foundation/NSArray.h>
#import <Foundation/NSByteOrder.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSEnumerator.h>
#import <Foundation/NSException.h>
#import <Foundation/NSHost.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSValue.h>

#import "GSStream.h"
#import "GSPrivate.h"
#import "GSSocketStream.h"

NSString * const NSStreamDataWrittenToMemoryStreamKey
  = @"NSStreamDataWrittenToMemoryStreamKey";
NSString * const NSStreamFileCurrentOffsetKey
  = @"NSStreamFileCurrentOffsetKey";

NSString * const NSStreamSocketSecurityLevelKey
  = @"NSStreamSocketSecurityLevelKey";
NSString * const NSStreamSocketSecurityLevelNone
  = @"NSStreamSocketSecurityLevelNone";
NSString * const NSStreamSocketSecurityLevelSSLv2
  = @"NSStreamSocketSecurityLevelSSLv2";
NSString * const NSStreamSocketSecurityLevelSSLv3
  = @"NSStreamSocketSecurityLevelSSLv3";
NSString * const NSStreamSocketSecurityLevelTLSv1
  = @"NSStreamSocketSecurityLevelTLSv1";
NSString * const NSStreamSocketSecurityLevelNegotiatedSSL
  = @"NSStreamSocketSecurityLevelNegotiatedSSL";
NSString * const NSStreamSocketSSLErrorDomain
  = @"NSStreamSocketSSLErrorDomain";
NSString * const NSStreamSOCKSErrorDomain
  = @"NSStreamSOCKSErrorDomain";
NSString * const NSStreamSOCKSProxyConfigurationKey
  = @"NSStreamSOCKSProxyConfigurationKey";
NSString * const NSStreamSOCKSProxyHostKey
  = @"NSStreamSOCKSProxyHostKey";
NSString * const NSStreamSOCKSProxyPasswordKey
  = @"NSStreamSOCKSProxyPasswordKey";
NSString * const NSStreamSOCKSProxyPortKey
  = @"NSStreamSOCKSProxyPortKey";
NSString * const NSStreamSOCKSProxyUserKey
  = @"NSStreamSOCKSProxyUserKey";
NSString * const NSStreamSOCKSProxyVersion4
  = @"NSStreamSOCKSProxyVersion4";
NSString * const NSStreamSOCKSProxyVersion5
  = @"NSStreamSOCKSProxyVersion5";
NSString * const NSStreamSOCKSProxyVersionKey
  = @"NSStreamSOCKSProxyVersionKey";

NSString * const GSStreamLocalAddressKey
  = @"GSStreamLocalAddressKey";
NSString * const GSStreamLocalPortKey
  = @"GSStreamLocalPortKey";
NSString * const GSStreamRemoteAddressKey
  = @"GSStreamRemoteAddressKey";
NSString * const GSStreamRemotePortKey
  = @"GSStreamRemotePortKey";


/*
 * Determine the type of event to use when adding a stream to the run loop.
 * By default add as an 'ET_TRIGGER' so that the stream will be notified
 * every time the loop runs (the event id/reference must be the address of
 * the stream itsself to ensure that event/type is unique).
 *
 * Streams which actually expect to wait for I/O events must be added with
 * the appropriate information for the loop to signal them.
 */
static RunLoopEventType typeForStream(NSStream *aStream)
{
#if	defined(__MINGW32__)
  if ([aStream _loopID] == (void*)aStream)
    {
      return ET_TRIGGER;
    }
  else
    {
      return ET_HANDLE;
    }
#else
  if ([aStream _loopID] == (void*)aStream)
    {
      return ET_TRIGGER;
    }
  else if ([aStream isKindOfClass: [NSOutputStream class]] == NO
    && [aStream  streamStatus] != NSStreamStatusOpening)
    {
      return ET_RDESC;
    }
  else
    {
      return ET_WDESC;	
    }
#endif
}

@implementation	NSRunLoop (NSStream)
- (void) addStream: (NSStream*)aStream mode: (NSString*)mode
{
  [self addEvent: [aStream _loopID]
	    type: typeForStream(aStream)
	 watcher: (id<RunLoopEvents>)aStream
	 forMode: mode];
}

- (void) removeStream: (NSStream*)aStream mode: (NSString*)mode
{
  [self removeEvent: [aStream _loopID]
	       type: typeForStream(aStream)
	    forMode: mode
		all: NO];
}
@end

@implementation GSStream

+ (void) initialize
{
  GSMakeWeakPointer(self, "delegate");
}

- (void) close
{
  if (_currentStatus == NSStreamStatusNotOpen)
    {
      NSDebugMLLog(@"NSStream", @"Attempt to close unopened stream %@", self);
    }
  [self _unschedule];
  [self _setStatus: NSStreamStatusClosed];
  /* We don't want to send any events to the delegate after the
   * stream has been closed.
   */
  _delegateValid = NO;
}

- (void) finalize
{
  if (_currentStatus != NSStreamStatusNotOpen
    && _currentStatus != NSStreamStatusClosed)
    {
      [self close];
    }
  GSAssignZeroingWeakPointer((void**)&_delegate, (void*)0);
}

- (void) dealloc
{
  [self finalize];
  if (_loops != 0)
    {
      NSFreeMapTable(_loops);
      _loops = 0;
    }
  DESTROY(_properties);
  DESTROY(_lastError);
  [super dealloc];
}

- (id) delegate
{
  return _delegate;
}

- (id) init
{
  if ((self = [super init]) != nil)
    {
      _delegate = self;
      _properties = nil;
      _lastError = nil;
      _loops = NSCreateMapTable(NSObjectMapKeyCallBacks,
	NSObjectMapValueCallBacks, 1);
      _currentStatus = NSStreamStatusNotOpen;
      _loopID = (void*)self;
    }
  return self;
}

- (void) open
{
  if (_currentStatus != NSStreamStatusNotOpen
    && _currentStatus != NSStreamStatusOpening)
    {
      NSDebugMLLog(@"NSStream", @"Attempt to re-open stream %@", self);
    }
  [self _setStatus: NSStreamStatusOpen];
  [self _schedule];
  [self _sendEvent: NSStreamEventOpenCompleted];
}

- (id) propertyForKey: (NSString *)key
{
  return [_properties objectForKey: key];
}

- (void) receivedEvent: (void*)data
                  type: (RunLoopEventType)type
		 extra: (void*)extra
	       forMode: (NSString*)mode
{
  [self _dispatch];
}

- (void) removeFromRunLoop: (NSRunLoop *)aRunLoop forMode: (NSString *)mode
{
  if (aRunLoop != nil && mode != nil)
    {
      NSMutableArray	*modes;

      modes = (NSMutableArray*)NSMapGet(_loops, (void*)aRunLoop);
      if ([modes containsObject: mode])
	{
	  [aRunLoop removeStream: self mode: mode];
	  [modes removeObject: mode];
	  if ([modes count] == 0)
	    {
	      NSMapRemove(_loops, (void*)aRunLoop);
	    }
	}
    }
}

- (void) scheduleInRunLoop: (NSRunLoop *)aRunLoop forMode: (NSString *)mode
{
  if (aRunLoop != nil && mode != nil)
    {
      NSMutableArray	*modes;

      modes = (NSMutableArray*)NSMapGet(_loops, (void*)aRunLoop);
      if (modes == nil)
	{
	  modes = [[NSMutableArray alloc] initWithCapacity: 1];
	  NSMapInsert(_loops, (void*)aRunLoop, (void*)modes);
	  RELEASE(modes);
	}
      if ([modes containsObject: mode] == NO)
	{
	  mode = [mode copy];
	  [modes addObject: mode];
	  RELEASE(mode);
	  /* We only add open streams to the runloop .. subclasses may add
	   * streams when they are in the process of opening if they need
	   * to do so.
	   */
	  if ([self _isOpened])
	    {
	      [aRunLoop addStream: self mode: mode];
	    }
	}
    }
}

- (void) setDelegate: (id)delegate
{
  if ([self streamStatus] == NSStreamStatusClosed
    || [self streamStatus] == NSStreamStatusError)
    {
      _delegateValid = NO;
      GSAssignZeroingWeakPointer((void**)&_delegate, (void*)0);
    }
  else
    {
      if (delegate == nil)
	{
	  _delegate = self;
	}
      if (delegate == self)
	{
	  if (_delegate != nil && _delegate != self)
	    {
              GSAssignZeroingWeakPointer((void**)&_delegate, (void*)0);
	    }
	  _delegate = delegate;
	}
      else
	{
          GSAssignZeroingWeakPointer((void**)&_delegate, (void*)delegate);
	}
      /* We don't want to send any events the the delegate after the
       * stream has been closed.
       */
      _delegateValid
        = [_delegate respondsToSelector: @selector(stream:handleEvent:)];
    }
}

- (BOOL) setProperty: (id)property forKey: (NSString *)key
{
  if (_properties == nil)
    {
      _properties = [NSMutableDictionary new];
    }
  [_properties setObject: property forKey: key];
  return YES;
}

- (NSError *) streamError
{
  return _lastError;
}

- (NSStreamStatus) streamStatus
{
  return _currentStatus;
}

@end


@implementation	NSStream (Private)

- (void) _dispatch
{
}

- (BOOL) _isOpened
{
  return NO;
}

- (void*) _loopID
{
  return (void*)self;	// By default a stream is a TRIGGER event.
}

- (void) _recordError
{
}

- (void) _recordError: (NSError*)anError
{
  return;
}

- (void) _resetEvents: (NSUInteger)mask
{
  return;
}

- (void) _schedule
{
}

- (void) _sendEvent: (NSStreamEvent)event
{
}

- (void) _setLoopID: (void *)ref
{
}

- (void) _setStatus: (NSStreamStatus)newStatus
{
}

- (BOOL) _unhandledData
{
  return NO;
}

- (void) _unschedule
{
}

@end

@implementation	GSStream (Private)

- (BOOL) _isOpened
{
  return !(_currentStatus == NSStreamStatusNotOpen
    || _currentStatus == NSStreamStatusOpening
    || _currentStatus == NSStreamStatusClosed);
}

- (void*) _loopID
{
  return _loopID;
}

- (void) _recordError
{
  NSError *theError;

  theError = [NSError _last];
  [self _recordError: theError];
}

- (void) _recordError: (NSError*)anError
{
  NSDebugMLLog(@"NSStream", @"record error: %@ - %@", self, anError);
  ASSIGN(_lastError, anError);
  _currentStatus = NSStreamStatusError;
}

- (void) _resetEvents: (NSUInteger)mask
{
  _events &= ~mask;
}

- (void) _schedule
{
  NSMapEnumerator	enumerator;
  NSRunLoop		*k;
  NSMutableArray	*v;

  enumerator = NSEnumerateMapTable(_loops);
  while (NSNextMapEnumeratorPair(&enumerator, (void **)(&k), (void**)&v))
    {
      unsigned	i = [v count];

      while (i-- > 0)
	{
	  [k addStream: self mode: [v objectAtIndex: i]];
	}
    }
  NSEndMapTableEnumeration(&enumerator);
}

- (void) _sendEvent: (NSStreamEvent)event
{
  if (event == NSStreamEventNone)
    {
      return;
    }
  else if (event == NSStreamEventOpenCompleted)
    {
      if ((_events & event) == 0)
	{
	  _events |= NSStreamEventOpenCompleted;
	  if (_delegateValid == YES)
	    {
	      [_delegate stream: self
		    handleEvent: NSStreamEventOpenCompleted];
	    }
	}
    }
  else if (event == NSStreamEventHasBytesAvailable)
    {
      if ((_events & NSStreamEventOpenCompleted) == 0)
	{
	  _events |= NSStreamEventOpenCompleted;
	  if (_delegateValid == YES)
	    {
	      [_delegate stream: self
		    handleEvent: NSStreamEventOpenCompleted];
	    }
	}
      if ((_events & NSStreamEventHasBytesAvailable) == 0)
	{
	  _events |= NSStreamEventHasBytesAvailable;
	  if (_delegateValid == YES)
	    {
	      [_delegate stream: self
		    handleEvent: NSStreamEventHasBytesAvailable];
	    }
	}
    }
  else if (event == NSStreamEventHasSpaceAvailable)
    {
      if ((_events & NSStreamEventOpenCompleted) == 0)
	{
	  _events |= NSStreamEventOpenCompleted;
	  if (_delegateValid == YES)
	    {
	      [_delegate stream: self
		    handleEvent: NSStreamEventOpenCompleted];
	    }
	}
      if ((_events & NSStreamEventHasSpaceAvailable) == 0)
	{
	  _events |= NSStreamEventHasSpaceAvailable;
	  if (_delegateValid == YES)
	    {
	      [_delegate stream: self
		    handleEvent: NSStreamEventHasSpaceAvailable];
	    }
	}
    }
  else if (event == NSStreamEventErrorOccurred)
    {
      if ((_events & NSStreamEventErrorOccurred) == 0)
	{
	  _events |= NSStreamEventErrorOccurred;
	  if (_delegateValid == YES)
	    {
	      [_delegate stream: self
		    handleEvent: NSStreamEventErrorOccurred];
	    }
	}
    }
  else if (event == NSStreamEventEndEncountered)
    {
      if ((_events & NSStreamEventEndEncountered) == 0)
	{
	  _events |= NSStreamEventEndEncountered;
	  if (_delegateValid == YES)
	    {
	      [_delegate stream: self
		    handleEvent: NSStreamEventEndEncountered];
	    }
	}
    }
  else
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"Unknown event (%d) passed to _sendEvent:", event];
    }
}

- (void) _setLoopID: (void *)ref
{
  _loopID = ref;
}

- (void) _setStatus: (NSStreamStatus)newStatus
{
  _currentStatus = newStatus;
}

- (BOOL) _unhandledData
{
  if (_events
    & (NSStreamEventHasBytesAvailable | NSStreamEventHasSpaceAvailable))
    {
      return YES;
    }
  return NO;
}

- (void) _unschedule
{
  NSMapEnumerator	enumerator;
  NSRunLoop		*k;
  NSMutableArray	*v;

  enumerator = NSEnumerateMapTable(_loops);
  while (NSNextMapEnumeratorPair(&enumerator, (void **)(&k), (void**)&v))
    {
      unsigned	i = [v count];

      while (i-- > 0)
	{
	  [k removeStream: self mode: [v objectAtIndex: i]];
	}
    }
  NSEndMapTableEnumeration(&enumerator);
}

- (BOOL) runLoopShouldBlock: (BOOL*)trigger
{
  if (_events
    & (NSStreamEventHasBytesAvailable | NSStreamEventHasSpaceAvailable))
    {
      /* If we have an unhandled data event, we should not watch for more
       * or trigger until the appropriate read or write has been done.
       */
      *trigger = NO;
      return NO;
    }
  if (_currentStatus == NSStreamStatusError)
    {
      if ((_events & NSStreamEventErrorOccurred) == 0)
	{
	  /* An error has occurred but not been handled,
	   * so we should trigger an error event at once.
	   */
	  *trigger = YES;
	  return NO;
	}
      else
	{
	  /* An error has occurred (and been handled),
	   * so we should not watch for any events at all.
	   */
	  *trigger = NO;
	  return NO;
	}
    }
  if (_currentStatus == NSStreamStatusAtEnd)
    {
      if ((_events & NSStreamEventEndEncountered) == 0)
	{
	  /* An end of stream has occurred but not been handled,
	   * so we should trigger an end of stream event at once.
	   */
	  *trigger = YES;
	  return NO;
	}
      else
	{
	  /* An end of stream has occurred (and been handled),
	   * so we should not watch for any events at all.
	   */
	  *trigger = NO;
	  return NO;
	}
    }

  if (_loopID == (void*)self)
    {
      /* If _loopID is the receiver, the stream is not receiving external
       * input, so it must trigger an event when the loop runs and must not
       * block the loop from running.
       */
      *trigger = YES;
      return NO;
    }
  else
    {
      *trigger = YES;
      return YES;
    }
}
@end

@implementation	GSInputStream

+ (void) initialize
{
  if (self == [GSInputStream class])
    {
      GSObjCAddClassBehavior(self, [GSStream class]);
      GSMakeWeakPointer(self, "delegate");
    }
}

- (BOOL) hasBytesAvailable
{
  if (_currentStatus == NSStreamStatusOpen)
    {
      return YES;
    }
  if (_currentStatus == NSStreamStatusAtEnd)
    {
      if ((_events & NSStreamEventEndEncountered) == 0)
	{
	  /* We have not sent the appropriate event yet, so the
           * client must not have issued a read:maxLength:
	   * (which is the point at which we should send).
	   */
	  return YES;
	}
    }
  return NO;
}

@end

@implementation	GSOutputStream

+ (void) initialize
{
  if (self == [GSOutputStream class])
    {
      GSObjCAddClassBehavior(self, [GSStream class]);
      GSMakeWeakPointer(self, "delegate");
    }
}

- (BOOL) hasSpaceAvailable
{
  if (_currentStatus == NSStreamStatusOpen)
    {
      return YES;
    }
  return NO;
}

@end


@implementation GSDataInputStream

/**
 * the designated initializer
 */ 
- (id) initWithData: (NSData *)data
{
  if ((self = [super init]) != nil)
    {
      ASSIGN(_data, data);
      _pointer = 0;
    }
  return self;
}

- (void) dealloc
{
  if ([self _isOpened])
    [self close];
  RELEASE(_data);
  [super dealloc];
}

- (NSInteger) read: (uint8_t *)buffer maxLength: (NSUInteger)len
{
  unsigned long dataSize;
  unsigned long copySize;

  if (buffer == 0)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"null pointer for buffer"];
    }
  if (len == 0)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"zero byte read write requested"];
    }

  _events &= ~NSStreamEventHasSpaceAvailable;

  if ([self streamStatus] == NSStreamStatusClosed)
    {
      return 0;
    }

  dataSize = [_data length];
  NSAssert(dataSize >= _pointer, @"Buffer overflow!");
  if (len + _pointer > dataSize)
    {
      copySize = dataSize - _pointer;
    }
  else
    {
      copySize = len;
    }
  if (copySize) 
    {
      memcpy(buffer, [_data bytes] + _pointer, copySize);
      _pointer = _pointer + copySize;
    }
  else
    {
      [self _setStatus: NSStreamStatusAtEnd];
    }
  return copySize;
}

- (BOOL) getBuffer: (uint8_t **)buffer length: (NSUInteger *)len
{
  unsigned long dataSize = [_data length];

  NSAssert(dataSize >= _pointer, @"Buffer overflow!");
  *buffer = (uint8_t*)[_data bytes] + _pointer;
  *len = dataSize - _pointer;
  return YES;
}

- (BOOL) hasBytesAvailable
{
  unsigned long dataSize = [_data length];

  return (dataSize > _pointer);
}

- (id) propertyForKey: (NSString *)key
{
  if ([key isEqualToString: NSStreamFileCurrentOffsetKey])
    return [NSNumber numberWithLong: _pointer];
  return [super propertyForKey: key];
}

- (void) _dispatch
{
  BOOL av = [self hasBytesAvailable];
  NSStreamEvent myEvent = av ? NSStreamEventHasBytesAvailable : 
    NSStreamEventEndEncountered;
  NSStreamStatus myStatus = av ? NSStreamStatusOpen : NSStreamStatusAtEnd;
  
  [self _setStatus: myStatus];
  [self _sendEvent: myEvent];
}

@end


@implementation GSBufferOutputStream

- (id) initToBuffer: (uint8_t *)buffer capacity: (NSUInteger)capacity
{
  if ((self = [super init]) != nil)
    {
      _buffer = buffer;
      _capacity = capacity;
      _pointer = 0;
    }
  return self;
}

- (NSInteger) write: (const uint8_t *)buffer maxLength: (NSUInteger)len
{
  if (buffer == 0)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"null pointer for buffer"];
    }
  if (len == 0)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"zero byte length write requested"];
    }

  _events &= ~NSStreamEventHasBytesAvailable;

  if ([self streamStatus] == NSStreamStatusClosed)
    {
      return 0;
    }

  if ((_pointer + len) > _capacity)
    {
      len = _capacity - _pointer;
      if (len == 0)
	{
	  [self _setStatus: NSStreamStatusAtEnd];
	  return 0;
	}
    }
  memcpy((_buffer + _pointer), buffer, len);
  _pointer += len;
  return len;
}

- (id) propertyForKey: (NSString *)key
{
  if ([key isEqualToString: NSStreamFileCurrentOffsetKey])
    {
      return [NSNumber numberWithLong: _pointer];
    }
  return [super propertyForKey: key];
}

- (void) _dispatch
{
  BOOL av = [self hasSpaceAvailable];
  NSStreamEvent myEvent = av ? NSStreamEventHasSpaceAvailable : 
    NSStreamEventEndEncountered;

  [self _sendEvent: myEvent];
}

@end

@implementation GSDataOutputStream

- (id) init
{
  if ((self = [super init]) != nil)
    {
      _data = [NSMutableData new];
      _pointer = 0;
    }
  return self;
}

- (void) dealloc
{
  RELEASE(_data);
  [super dealloc];
}

- (NSInteger) write: (const uint8_t *)buffer maxLength: (NSUInteger)len
{
  if (buffer == 0)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"null pointer for buffer"];
    }
  if (len == 0)
    {
      [NSException raise: NSInvalidArgumentException
		  format: @"zero byte length write requested"];
    }

  _events &= ~NSStreamEventHasBytesAvailable;

  if ([self streamStatus] == NSStreamStatusClosed)
    {
      return 0;
    }

  [_data appendBytes: buffer length: len];
  _pointer += len;
  return len;
}

- (BOOL) hasSpaceAvailable
{
  return YES;
}

- (id) propertyForKey: (NSString *)key
{
  if ([key isEqualToString: NSStreamFileCurrentOffsetKey])
    {
      return [NSNumber numberWithLong: _pointer];
    }
  else if ([key isEqualToString: NSStreamDataWrittenToMemoryStreamKey])
    {
      return _data;
    }
  return [super propertyForKey: key];
}

- (void) _dispatch
{
  BOOL av = [self hasSpaceAvailable];
  NSStreamEvent myEvent = av ? NSStreamEventHasSpaceAvailable : 
    NSStreamEventEndEncountered;

  [self _sendEvent: myEvent];
}

@end


@implementation GSServerStream

static Class	localServerClass = 0;

+ (void) initialize
{
  GSMakeWeakPointer(self, "delegate");
  if (localServerClass == 0)
    {
      localServerClass = NSClassFromString(@"GSLocalServerStream");
    }
}

+ (id) serverStreamToAddr: (NSString*)addr port: (NSInteger)port
{
  GSServerStream *s;

  // try inet first, then inet6
  s = [[GSInetServerStream alloc] initToAddr: addr port: port];
  if (!s)
    s = [[GSInet6ServerStream alloc] initToAddr: addr port: port];
  return AUTORELEASE(s);
}

+ (id) serverStreamToAddr: (NSString*)addr
{
  return AUTORELEASE([[localServerClass alloc] initToAddr: addr]);
}

- (id) initToAddr: (NSString*)addr port: (NSInteger)port
{
  RELEASE(self);
  // try inet first, then inet6
  self = [[GSInetServerStream alloc] initToAddr: addr port: port];
  if (!self)
    self = [[GSInet6ServerStream alloc] initToAddr: addr port: port];
  return self;
}

- (id) initToAddr: (NSString*)addr
{
  RELEASE(self);
  return [[localServerClass alloc] initToAddr: addr];
}

- (void) acceptWithInputStream: (NSInputStream **)inputStream 
                  outputStream: (NSOutputStream **)outputStream
{
  [self subclassResponsibility: _cmd];
}

@end

@implementation GSAbstractServerStream

+ (void) initialize
{
  if (self == [GSAbstractServerStream class])
    {
      GSObjCAddClassBehavior(self, [GSStream class]);
    }
}

@end

