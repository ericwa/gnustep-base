/* Interface for NSMethodSignature for GNUStep
   Copyright (C) 1995 Free Software Foundation, Inc.

   Written by:  Mike Kienenberger
   Date: Jun 1998
   
   This file is part of the GNUstep Base Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Library General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.
   
   You should have received a copy of the GNU Library General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
   */ 

#import <Foundation/NSProtocolChecker.h>
#import <Foundation/NSException.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>

@implementation NSProtocolChecker

// Allocates and initializes an NSProtocolChecker instance that will
// forward any messages in the aProtocol protocol to anObject, its
// target. Thus, the checker can be vended in lieu of anObject to
// restrict the messages that can be sent to anObject. Returns the
// new instance.

+ (id)protocolCheckerWithTarget:(NSObject *)anObject
			protocol:(Protocol *)aProtocol
{
  return [[[NSProtocolChecker alloc] initWithTarget:anObject
				    protocol:aProtocol] autorelease];
}

// Forwards any message to the delegate if the method is declared in
// the checker's protocol; otherwise raises an NSInvalidArgumentException.

- (void)forwardInvocation:(NSInvocation *)anInvocation
{
  unsigned int length;
  void *buffer;
  
  if ((struct objc_method_description *)NULL
      != [self methodDescriptionForSelector:[anInvocation selector]])
    [[NSException exceptionWithName:NSInvalidArgumentException
		  reason:@"Method not declared in current protocol"
		  userInfo:nil]
      raise];
      
  [anInvocation invokeWithTarget:myTarget];
  
  length = [[anInvocation methodSignature] methodReturnLength];
  buffer = (void *)malloc(length);
  [anInvocation getReturnValue:buffer];
  
  if (0 == strcmp([[anInvocation methodSignature] methodReturnType],
		  [[anInvocation methodSignatureForSelector: 
				  @selector(init:)] methodReturnType]) )
    {
      if (((id)buffer) == myTarget)
   	{
	  ((id)buffer) = self;
	  [anInvocation setReturnValue: buffer];
   	}
    }
  
  return;
}


- (id)init
{
  myProtocol = nil;
  myTarget = nil;
  
  return self;
}

// Initializes a newly allocated NSProtocolChecker instance that will
// forward any messages in the aProtocol protocol to anObject, its
// delegate. Thus, the checker can be vended in lieu of anObject to
// restrict the messages that can be sent to anObject. If anObject is
// allowed to be freed or dereferenced by clients, the free method
// should be included in aProtocol. Returns the new instance.

- (id)initWithTarget:(NSObject *)anObject protocol:(Protocol *)aProtocol
{
  [super init];
  
  //if (nil != myProtocol)  
  //  [myProtocol autorelease];
  myProtocol = aProtocol;
  //if (nil != myProtocol)  
  //  [myProtocol retain];
  
  if (nil != myTarget)  
    [myTarget autorelease];
  myTarget = anObject;
  if (nil != myTarget)  
    [myTarget retain];
  
  return self;
}

// Returns an Objective C description for a method in the checker's
// protocol, or NULL if aSelector isn't declared as an instance method
// in the protocol.

- (struct objc_method_description *)methodDescriptionForSelector:(SEL)aSelector
{
  return [myProtocol descriptionForInstanceMethod:aSelector];
}

// Returns the protocol object the checker uses to verify whether a
// given message should be forwarded to its delegate, or the protocol
// checker should raise an NSInvalidArgumentException.

- (Protocol *)protocol
{
  if (nil == myProtocol)
    [[NSException exceptionWithName:NSInvalidArgumentException
		  reason:@"No protocol specified"
		  userInfo:nil]
      raise];
  
  return myProtocol;
}

// Returns the target of the NSProtocolChecker.

- (NSObject *)target
{
  return myTarget;
}

@end
