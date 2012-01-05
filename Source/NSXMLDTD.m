/* Inmplementation for NSXMLDTD for GNUStep
   Copyright (C) 2008 Free Software Foundation, Inc.

   Written by:  Richard Frith-Macdonald <rfm@gnu.org>
   Created: September 2008

   This file is part of the GNUstep Base Library.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 3 of the License, or (at your option) any later version.
   
   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.
*/

#import "common.h"

#define GSInternal              NSXMLDTDInternal
#import "NSXMLPrivate.h"
#import "GSInternal.h"
GS_PRIVATE_INTERNAL(NSXMLDTD)

@implementation NSXMLDTD

+ (NSXMLDTDNode*) predefinedEntityDeclarationForName: (NSString*)name
{
  [self notImplemented: _cmd];
  return nil;
}

- (void) dealloc
{
  if (GS_EXISTS_INTERNAL)
    {
      [internal->publicID release];
      [internal->systemID release];
      [internal->entities release];
      [internal->elements release];
      [internal->notations release];
      [internal->attributes release];
      [internal->original release];
    }
  [super dealloc];
}

- (void) addChild: (NSXMLNode*)child
{
  [self notImplemented: _cmd];
}

- (NSXMLDTDNode*) attributeDeclarationForName: (NSString*)name
                                   elementName: (NSString*)elementName
{
  [self notImplemented: _cmd];
  return nil;
}

- (NSXMLDTDNode*) elementDeclarationForName: (NSString*)name
{
  [self notImplemented: _cmd];
  return nil;
}

- (NSXMLDTDNode*) entityDeclarationForName: (NSString*)name
{
  [self notImplemented: _cmd];
  return nil;
}

- (id) init
{
  return [self initWithKind: NSXMLDTDKind options: 0];
}

- (id) initWithContentsOfURL: (NSURL*)url
                     options: (NSUInteger)mask
                       error: (NSError**)error
{
  NSData	*data;
  NSXMLDTD	*doc;

  data = [NSData dataWithContentsOfURL: url];
  doc = [self initWithData: data options: 0 error: 0];
  [doc setURI:  [url absoluteString]];
  return doc;
}

- (id) initWithData: (NSData*)data
            options: (NSUInteger)mask
              error: (NSError**)error
{
  [self notImplemented: _cmd];
  return nil;
}

- (id) initWithKind: (NSXMLNodeKind)kind options: (NSUInteger)theOptions
{
  if (NSXMLDTDKind == kind)
    {
      /* Create holder for internal instance variables so that we'll have
       * all our ivars available rather than just those of the superclass.
       */
      GS_CREATE_INTERNAL(NSXMLDTD)
    }
  return [super initWithKind: kind options: theOptions];
}

- (void) insertChild: (NSXMLNode*)child atIndex: (NSUInteger)index
{
  [self notImplemented: _cmd];
  internal->childrenHaveMutated = YES;
}

- (void) insertChildren: (NSArray*)children atIndex: (NSUInteger)index
{
  NSEnumerator	*enumerator = [children objectEnumerator];
  NSXMLNode	*child;

  while ((child = [enumerator nextObject]) != nil)
    {
      [self insertChild: child atIndex: index++];
    }
}

- (NSXMLDTDNode*) notationDeclarationForName: (NSString*)name
{
  NSXMLDTDNode	*notation = [internal->notations objectForKey: name];

  if (notation == nil)
    {
      [self notImplemented: _cmd];
    }
  return notation;
}

- (NSString*) publicID
{
  if (internal->publicID == nil)
    {
      [self notImplemented: _cmd];
    }
  return internal->publicID;
}

- (void) removeChildAtIndex: (NSUInteger)index
{
  [self notImplemented: _cmd];
}

- (void) replaceChildAtIndex: (NSUInteger)index withNode: (NSXMLNode*)node
{
  [self notImplemented: _cmd];
}

- (void) setChildren: (NSArray*)children
{
  [self notImplemented: _cmd];
}

- (void) setPublicID: (NSString*)publicID
{
  [self notImplemented: _cmd];
  internal->modified = YES;
}

- (void) setSystemID: (NSString*)systemID
{
  [self notImplemented: _cmd];
  internal->modified = YES;
}

- (NSString*) systemID
{
  if (internal->systemID == nil)
    {
      [self notImplemented: _cmd];
    }
  return internal->systemID;
}

@end

