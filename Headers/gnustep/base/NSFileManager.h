/* 
   NSFileManager.h

   Copyright (C) 1997,1999 Free Software Foundation, Inc.

   Author: Mircea Oancea <mircea@jupiter.elcom.pub.ro>
   Author: Ovidiu Predescu <ovidiu@net-community.com>
   Date: Feb 1997

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
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.
*/

#ifndef __NSFileManager_h_GNUSTEP_BASE_INCLUDE
#define __NSFileManager_h_GNUSTEP_BASE_INCLUDE

#include <Foundation/NSObject.h>

#ifndef	STRICT_OPENSTEP
#include <Foundation/NSUtilities.h>
#include <Foundation/NSDictionary.h>

@class NSNumber;
@class NSString;
@class NSData;
@class NSDate;
@class NSArray;
@class NSMutableArray;

@class NSDirectoryEnumerator;

@interface NSFileManager : NSObject
{
  NSString	*_lastError;
}

// Getting the default manager
+ (NSFileManager*) defaultManager;

// Directory operations
- (BOOL) changeCurrentDirectoryPath: (NSString*)path;
- (BOOL) createDirectoryAtPath: (NSString*)path
		    attributes: (NSDictionary*)attributes;
- (NSString*) currentDirectoryPath;

// File operations
- (BOOL) copyPath: (NSString*)source
	   toPath: (NSString*)destination
	  handler: (id)handler;
- (BOOL) movePath: (NSString*)source
	   toPath: (NSString*)destination 
	  handler: (id)handler;
- (BOOL) linkPath: (NSString*)source
	   toPath: (NSString*)destination
	  handler: (id)handler;
- (BOOL) removeFileAtPath: (NSString*)path
		  handler: (id)handler;
- (BOOL) createFileAtPath: (NSString*)path
		 contents: (NSData*)contents
	       attributes: (NSDictionary*)attributes;

// Getting and comparing file contents	
- (NSData*) contentsAtPath: (NSString*)path;
- (BOOL) contentsEqualAtPath: (NSString*)path1
		     andPath: (NSString*)path2;

// Detemining access to files
- (BOOL) fileExistsAtPath: (NSString*)path;
- (BOOL) fileExistsAtPath: (NSString*)path isDirectory: (BOOL*)isDirectory;
- (BOOL) isReadableFileAtPath: (NSString*)path;
- (BOOL) isWritableFileAtPath: (NSString*)path;
- (BOOL) isExecutableFileAtPath: (NSString*)path;
- (BOOL) isDeletableFileAtPath: (NSString*)path;

// Getting and setting attributes
- (NSDictionary*) fileAttributesAtPath: (NSString*)path
			  traverseLink: (BOOL)flag;
- (NSDictionary*) fileSystemAttributesAtPath: (NSString*)path;
- (BOOL) changeFileAttributes: (NSDictionary*)attributes
		       atPath: (NSString*)path;

// Discovering directory contents
- (NSArray*) directoryContentsAtPath: (NSString*)path;
- (NSDirectoryEnumerator*) enumeratorAtPath: (NSString*)path;
- (NSArray*) subpathsAtPath: (NSString*)path;

// Symbolic-link operations
- (BOOL) createSymbolicLinkAtPath: (NSString*)path
		      pathContent: (NSString*)otherPath;
- (NSString*) pathContentOfSymbolicLinkAtPath: (NSString*)path;

// Converting file-system representations
- (const char*) fileSystemRepresentationWithPath: (NSString*)path;
- (NSString*) stringWithFileSystemRepresentation: (const char*)string
					  length: (unsigned int)len;

@end /* NSFileManager */


@interface NSObject (NSFileManagerHandler)
- (BOOL) fileManager: (NSFileManager*)fileManager
  shouldProceedAfterError: (NSDictionary*)errorDictionary;
- (void) fileManager: (NSFileManager*)fileManager
  willProcessPath: (NSString*)path;
@end


@interface NSDirectoryEnumerator : NSEnumerator
{
  NSMutableArray	*_enumStack;
  NSMutableArray	*_pathStack;
  NSString		*_currentFileName;
  NSString		*_currentFilePath;
  NSString		*_topPath;
  NSDictionary		*_directoryAttributes;
  NSDictionary		*_fileAttributes;
  struct {
      BOOL		isRecursive: 1;
      BOOL		isFollowing: 1;
   } _flags;
}

// Initializing
- (id) initWithDirectoryPath: (NSString*)path 
   recurseIntoSubdirectories: (BOOL)recurse
	      followSymlinks: (BOOL)follow
		 prefixFiles: (BOOL)prefix;

// Getting attributes
- (NSDictionary*) directoryAttributes;
- (NSDictionary*) fileAttributes;

// Skipping subdirectories
- (void) skipDescendents;

@end /* NSDirectoryEnumerator */

/* File Attributes */
extern NSString* const NSFileDeviceIdentifier;
extern NSString* const NSFileGroupOwnerAccountName;
extern NSString* const NSFileDeviceIdentifier;
extern NSString* const NSFileModificationDate;
extern NSString* const NSFileOwnerAccountName;
extern NSString* const NSFilePosixPermissions;
extern NSString* const NSFileReferenceCount;
extern NSString* const NSFileSize;
extern NSString* const NSFileSystemFileNumber;
extern NSString* const NSFileSystemNumber;
extern NSString* const NSFileType;

#ifndef	STRICT_MACOS_X
extern NSString* const NSFileGroupOwnerAccountNumber;
extern NSString* const NSFileOwnerAccountNumber;
#endif

/* File Types */

extern NSString* const NSFileTypeDirectory;
extern NSString* const NSFileTypeRegular;
extern NSString* const NSFileTypeSymbolicLink;
extern NSString* const NSFileTypeSocket;
extern NSString* const NSFileTypeFifo;
extern NSString* const NSFileTypeCharacterSpecial;
extern NSString* const NSFileTypeBlockSpecial;
extern NSString* const NSFileTypeUnknown;

/* FileSystem Attributes */

extern NSString* const NSFileSystemSize;
extern NSString* const NSFileSystemFreeSize;
extern NSString* const NSFileSystemNodes;
extern NSString* const NSFileSystemFreeNodes;

/* Easy access to attributes in a dictionary */

@interface NSDictionary(NSFileAttributes)
- (unsigned long long) fileSize;
- (NSString*) fileType;
- (NSString*) fileOwnerAccountName;
- (NSString*) fileGroupOwnerAccountName;
- (NSDate*) fileModificationDate;
- (unsigned long) filePosixPermissions;
- (unsigned long) fileSystemNumber;
- (unsigned long) fileSystemFileNumber;

#ifndef	STRICT_MACOS_X
- (unsigned long) fileOwnerAccountNumber;
- (unsigned long) fileGroupOwnerAccountNumber;
#endif
@end

#endif
#endif /* __NSFileManager_h_GNUSTEP_BASE_INCLUDE */
