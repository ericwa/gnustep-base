/* Interface for GSFileHandle for GNUStep
   Copyright (C) 1997-2002 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <richard@brainstorm.co.uk>
   Date: 1997

   This file is part of the GNUstep Base Library.

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

#ifndef __GSFileHandle_h_GNUSTEP_BASE_INCLUDE
#define __GSFileHandle_h_GNUSTEP_BASE_INCLUDE

#include <Foundation/NSFileHandle.h>
#include <Foundation/NSArray.h>
#include <Foundation/NSDictionary.h>
#include <Foundation/NSRunLoop.h>

#include <GNUstepBase/GSConfig.h>

#if	USE_ZLIB
#include <zlib.h>
#endif

@interface GSFileHandle : NSFileHandle <RunLoopEvents, GCFinalization>
{
  int			descriptor;
  BOOL			closeOnDealloc;
  BOOL			isStandardFile;
  BOOL			isNullDevice;
  BOOL			isSocket;
  BOOL			isNonBlocking;
  BOOL			wasNonBlocking;
  BOOL			acceptOK;
  BOOL			connectOK;
  BOOL			readOK;
  BOOL			writeOK;
  NSMutableDictionary	*readInfo;
  int			readMax;
  NSMutableArray	*writeInfo;
  int			writePos;
  NSString		*address;
  NSString		*service;
  NSString		*protocol;
#if	USE_ZLIB
  gzFile		gzDescriptor;
#endif
#if	defined(__MINGW32__)
  WSAEVENT  		event;
#endif
}

- (id) initAsClientAtAddress: (NSString*)address
		     service: (NSString*)service
		    protocol: (NSString*)protocol;
- (id) initAsClientInBackgroundAtAddress: (NSString*)address
				 service: (NSString*)service
				protocol: (NSString*)protocol
				forModes: (NSArray*)modes;
- (id) initAsServerAtAddress: (NSString*)address
		     service: (NSString*)service
		    protocol: (NSString*)protocol;
- (id) initForReadingAtPath: (NSString*)path;
- (id) initForWritingAtPath: (NSString*)path;
- (id) initForUpdatingAtPath: (NSString*)path;
- (id) initWithStandardError;
- (id) initWithStandardInput;
- (id) initWithStandardOutput;
- (id) initWithNullDevice;

- (void) checkAccept;
- (void) checkConnect;
- (void) checkRead;
- (void) checkWrite;

- (void) ignoreReadDescriptor;
- (void) ignoreWriteDescriptor;
- (void) setNonBlocking: (BOOL)flag;
- (void) postReadNotification;
- (void) postWriteNotification;
- (int) read: (void*)buf length: (int)len;
- (void) receivedEvent: (void*)data
		  type: (RunLoopEventType)type
	         extra: (void*)extra
	       forMode: (NSString*)mode;
- (void) setAddr: (struct sockaddr_in *)sin;
- (BOOL) useCompression;
- (void) watchReadDescriptorForModes: (NSArray*)modes;
- (void) watchWriteDescriptor;
- (int) write: (const void*)buf length: (int)len;

@end

#endif /* __GSFileHandle_h_GNUSTEP_BASE_INCLUDE */
