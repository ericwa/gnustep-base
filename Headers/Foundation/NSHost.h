/* Interface for host class
   Copyright (C) 1996, 1997 Free Software Foundation, Inc.

   Written by: Luke Howard <lukeh@xedoc.com.au> 
   Date: 1996
   
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
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
   MA 02111 USA.
   */ 
#ifndef __NSHost_h_GNUSTEP_BASE_INCLUDE
#define __NSHost_h_GNUSTEP_BASE_INCLUDE

#include <Foundation/NSObject.h>

@class NSString, NSArray, NSSet;

/**
 *  Instances of this class encapsulate host information.  Constructors based
 *  on host name or numeric address are provided.
 */
@interface NSHost : NSObject
{
  @private
  NSSet	*_names;
  NSSet	*_addresses;
}

/**
 * Get current host object.
 */
+ (NSHost*) currentHost;

/**
 *  Get info for host with given DNS name.
 */
+ (NSHost*) hostWithName: (NSString*)name;

/**
 *  Get a host object.  Hosts are cached for efficiency.  The address
 *  must be an IPV4 "dotted decimal" string, e.g.
 <example>
  NSHost aHost = [NSHost hostWithAddress:@"192.42.172.1"];
 </example>
 */
+ (NSHost*) hostWithAddress: (NSString*)address;

/**
 * Set host cache management.
 * If enabled, only one object representing each host will be created, and
 * a shared instance will be returned by all methods that return a host.
 */
+ (void) setHostCacheEnabled: (BOOL)flag;

/**
 * Return host cache management.
 * If enabled, only one object representing each host will be created, and
 * a shared instance will be returned by all methods that return a host.
 */
+ (BOOL) isHostCacheEnabled;

/**
 * Clear cache of host info instances.
 */
+ (void) flushHostCache;

/**
 * Compare hosts.
 * Hosts are equal if they share at least one address
 */
- (BOOL) isEqualToHost: (NSHost*) aHost;

/**
 * Return host name.  Chosen arbitrarily if a host has more than one.
 */
- (NSString*) name;

/**
 * Return all known names for host.
 */
- (NSArray*) names;

/**
 * Return host address in "dotted decimal" notation, e.g. "192.42.172.1".
 * Chosen arbitrarily if a host has more than one.
 */
- (NSString*) address;

/**
 * Return all known addresses for host in "dotted decimal" notation,
 * e.g. "192.42.172.1".
 */
- (NSArray*) addresses;

@end

/**
 *  Adds synonym for +currentHost.
 */
@interface NSHost (GNUstep)

/**
 *  Synonym for +currentHost.
 */
+ (NSHost*) localHost;		/* All local IP addresses	*/
@end

#endif

