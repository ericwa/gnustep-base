/* Test/example program for the base library

   Copyright (C) 2005 Free Software Foundation, Inc.
   
  Copying and distribution of this file, with or without modification,
  are permitted in any medium without royalty provided the copyright
  notice and this notice are preserved.

   This file is part of the GNUstep Base Library.
*/
#include <Foundation/NSProcessInfo.h>
#include <Foundation/NSString.h>
#include <Foundation/NSArray.h>
#include <Foundation/NSDictionary.h>
#include <Foundation/NSDate.h>
#include    <Foundation/NSAutoreleasePool.h>

int main(int argc, char *argv[])
{
  NSAutoreleasePool	*arp = [NSAutoreleasePool new];
  NSProcessInfo *pi = [NSProcessInfo processInfo];
  NSString* aString;
  NSString* aKey;
  NSEnumerator* enumerator;

  printf("Host name: %s\n",[[pi hostName] cString]);
  printf("Operating system: %d\n",[pi operatingSystem]);
  printf("Operating system name: %s\n",[[pi operatingSystemName] cString]);
  printf("Process Name: %s\n",[[pi processName] cString]);
  printf("Globally Unique String: %s\n",[[pi globallyUniqueString] cString]);

  printf("\nProcess arguments\n");
  printf("%d argument(s)\n", [[pi arguments] count]);
  enumerator = [[pi arguments] objectEnumerator];
  while ((aString = [enumerator nextObject]))
    printf("-->%s\n",[aString cString]);

  printf("\nProcess environment\n");
  printf("%d environment variables(s)\n", [[pi environment] count]);
  enumerator = [[pi environment] keyEnumerator];
  while ((aKey = [enumerator nextObject]))
    printf("++>%s=%s\n",[aKey cString],[[[pi environment]
				       objectForKey:aKey] cString]);

  [arp release];
  exit(0);
}
