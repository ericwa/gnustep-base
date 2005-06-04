/**
   NSFileManager.h

   Copyright (C) 1997,1999-2005 Free Software Foundation, Inc.

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
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02111 USA.


<chapter>
  <heading>File management</heading>
  <section>
    <heading>Path handling</heading>
    <p>The rules for path handling depend on the value in the
    <code>GSPathHandling</code> user default and, to some extent,
    on the platform on which the program mis running.<br />
    The understood values of GSPathHandling are <em>unix</em>
    and <em>windows</em>.  If GSPathHandling is any other value
    (or has not been set), GNUstep interprets this as meaning
    it should try to <em>do-the-right-thing</em><br />
    In the default mode of operation the system is very tolerant
    of paths and allows you to work with both unix and windows
    style paths.  The consequences of this are apparent in the 
    path handling methods of [NSString] rather than in [NSFileManager].
    </p>
    <subsect>
      <heading>unix</heading>
      <p>On all Unix platforms, Path components are separated by slashes
      and file names may contain any character other than slash.<br />
      The file names . and .. are special cases meaning current directory
      and the parent of the current directory respectively.<br />
      Multiple adjacent slash characters are treated as a single separator.
      </p>
      Here are various examples:
      <deflist>
	<term>/</term>
	<desc>An absolute path to the root directory. 
	</desc>
	<term>/etc/motd</term>
	<desc>An absolute path to the file named <em>motd</em>
	in the subdirectory <em>etc</em> of the root directory. 
	</desc>
	<term>..</term>
	<desc>A relative path to the parent of the current directory. 
	</desc>
	<term>program.m</term>
	<desc>A relative path to the file <em>program.m</em>
	in the current directory. 
	</desc>
	<term>Source/program.m</term>
	<desc>A relative path to the file <em>program.m</em> in the
	subdirectory <em>Source</em> of the current directory. 
	</desc>
	<term>../GNUmakefile</term>
	<desc>A relative path to the file <em>GNUmakefile</em>
	in the directory above the current directory.
	</desc>
      </deflist>
    </subsect>
    <subsect>
      <heading>windows</heading>
      <p>On Microsoft Windows the native paths may be either UNC
      or drive-relative, so GNUstep supports both.<br />
      Either or both slash (/) and backslash (\) may be used as
      separators for path components in either type of name.<br />
      UNC paths follow the general form //host/share/path/file,
      but must at least contain the host and share parts,
      i.e. //host/share is a UNC path, but //host is <em>not</em><br />
      Drive-relative names consist of an optional drive specifier
      (consisting of a single letter followed by a single colon)
      followed by an absolute or relative path.<br />
      In both forms, the names . and .. are refer to the curtrent
      directory and the parent directory as in unix paths.
      </p>
      Here are various examples:
      <deflist>
	<term>//host/share/file</term>
	<desc>An absolute UNC path to a file called <em>file</em>
	in the top directory of the export point share on host.
	</desc>
	<term>C:</term>
	<desc>A relative path to the current directory on drive C.
	</desc>
	<term>C:program.m</term>
	<desc>A relative path to the file <em>program.m</em> on drive C.
	</desc>
	<term>C:\program.m</term>
	<desc>An absolute path to the file <em>program.m</em>
	in the top level directory on drive C.
	</desc>
	<term>/Source\program.m</term>
	<desc>A drive-relative path to <em>program.m</em> in the directory
	<em>Source</em> on the current drive.
	</desc>
	<term>\\name</term>
	<desc>A drive-relative path to <em>name</em> in the top level directory
	on the current drive.  The '\\' is treated as a single backslash as
	this is not a UNC name (there must be both a host and a share part in
	a UNC name).
	</desc>
      </deflist>
    </subsect>
    <subsect>
      <heading>gnustep</heading>
      <p>In the default mode, GNUstep handles both unix and windows paths so
      it treats both slash (/) and backslash (\) as separators and understands
      the windows UNC and drive relative path roots.<br />
      However, it treats any path beginning with a slash (/) as an absolute
      path <em>if running on a unix system</em>.
      </p>
    </subsect>
    <subsect>
      <heading>Portability</heading>
      <p>Attempting to pass absolute paths between applications working on
      different systems is fraught with difficulty ... just don't do it.<br />
      Where paths need to be passed around (eg. in property lists or archives)
      you should pass relative paths and use a standard mechanism to construct
      an absolute path in the receiving application, for instance, appending
      the relative path to the home directory of a user.
      </p>
      Even using relative paths you should take care ...
      <list>
        <item>Use only the slash (/) as a path separator, not backslash (\).
	</item>
        <item>Never use a backslash (\) in a file name.
	</item>
        <item>Avoid colons in file names.
	</item>
        <item>Use no more than three letters in a path extension.
	</item>
      </list>
      Remember that, while GNUstep will manipulate both windows and unix
      paths, any path actually used to reference a file or directory
      must be valid on the local system.
    </subsect>
    <subsect>
      <heading>Tilde substitution</heading>
      <p>GNUstep handles substitution of tilde (~) as foillows:<br />
      If a path is just ~ or begins ~/ then the value returned by
      NSHomeDirectory() is substituted for the tilde.<br />
      If a path is of the form ~name or begins wityh a string like ~name/
      then name is used as the argument to NSHomeDirectoryForUser() and
      the return value from that method (if non-nil) is used to replace
      the tilde.
      </p>
    </subsect>
  </section>
</chapter>
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

+ (NSFileManager*) defaultManager;

- (BOOL) changeCurrentDirectoryPath: (NSString*)path;
- (BOOL) changeFileAttributes: (NSDictionary*)attributes
		       atPath: (NSString*)path;
- (NSArray*) componentsToDisplayForPath: (NSString*)path;
- (NSData*) contentsAtPath: (NSString*)path;
- (BOOL) contentsEqualAtPath: (NSString*)path1
		     andPath: (NSString*)path2;
- (BOOL) copyPath: (NSString*)source
	   toPath: (NSString*)destination
	  handler: (id)handler;
- (BOOL) createDirectoryAtPath: (NSString*)path
		    attributes: (NSDictionary*)attributes;
- (BOOL) createFileAtPath: (NSString*)path
		 contents: (NSData*)contents
	       attributes: (NSDictionary*)attributes;
- (BOOL) createSymbolicLinkAtPath: (NSString*)path
		      pathContent: (NSString*)otherPath;
- (NSString*) currentDirectoryPath;
- (NSArray*) directoryContentsAtPath: (NSString*)path;
- (NSString*) displayNameAtPath: (NSString*)path;
- (NSDirectoryEnumerator*) enumeratorAtPath: (NSString*)path;
- (NSDictionary*) fileAttributesAtPath: (NSString*)path
			  traverseLink: (BOOL)flag;
- (BOOL) fileExistsAtPath: (NSString*)path;
- (BOOL) fileExistsAtPath: (NSString*)path isDirectory: (BOOL*)isDirectory;
- (NSDictionary*) fileSystemAttributesAtPath: (NSString*)path;
- (const char*) fileSystemRepresentationWithPath: (NSString*)path;
#ifndef NO_GNUSTEP
- (NSString*) localFromOpenStepPath:(NSString*)path;
- (NSString*) openStepPathFromLocal:(NSString*)localPath;
#endif
- (BOOL) isExecutableFileAtPath: (NSString*)path;
- (BOOL) isDeletableFileAtPath: (NSString*)path;
- (BOOL) isReadableFileAtPath: (NSString*)path;
- (BOOL) isWritableFileAtPath: (NSString*)path;
- (BOOL) linkPath: (NSString*)source
	   toPath: (NSString*)destination
	  handler: (id)handler;
- (BOOL) movePath: (NSString*)source
	   toPath: (NSString*)destination 
	  handler: (id)handler;
- (NSString*) pathContentOfSymbolicLinkAtPath: (NSString*)path;
- (BOOL) removeFileAtPath: (NSString*)path
		  handler: (id)handler;
- (NSString*) stringWithFileSystemRepresentation: (const char*)string
					  length: (unsigned int)len;
- (NSArray*) subpathsAtPath: (NSString*)path;

@end /* NSFileManager */

/**
 * An informal protocol to which handler objects should conform
 * if they wish to deal with copy and move operations performed
 * by NSFileManager.
 */
@interface NSObject (NSFileManagerHandler)
/**
 * <p>When an error occurs during a copy or move operation, the file manager
 * will send this message to the handler, and will use the return value to
 * determine whether the operation should proceed.  If the method returns
 * YES then the operation will proceed after the error, if it returns NO
 * then it will be aborted.
 * </p>
 * <p>If the handler does not implement this method it will be treated as
 * if it returns NO.
 * </p>
 * The error dictionary contains the following
 * <list>
 *   <item><strong>"Error"</strong>
 *     contains a description of the error.
 *   </item>
 *   <item><strong>"Path"</strong>
 *     contains the path that is being processed when
 *     an error occured.   If an error occurs during an
 *     operation involving two files, like copying, and
 *     it is not clear which file triggers the error it
 *     will default to the source file.
 *   </item>          
 *   <item><strong>"FromPath"</strong>
 *     (Optional)  contains the path involved in reading.
 *   </item>
 *   <item><strong>"ToPath"</strong>
 *     (Optional)  contains the path involved in writing.
 *   </item>
 * </list>
 *
 * <p>Note that the <code>FromPath</code> is a GNUstep extension.
 * </p>
 * <p>Also the <code>FromPath</code> and <code>ToPath</code> are filled
 * in when appropriate.  So when copying a file they will typically
 * both have a value and when reading only <code>FromPath</code>.
 * </p>
 */
- (BOOL) fileManager: (NSFileManager*)fileManager
  shouldProceedAfterError: (NSDictionary*)errorDictionary;

/**
 * The file manager sends this method to the handler immediately before
 * performing part of a directory move or copy operation.  This provides
 * the handler object with information it can use in the event of an
 * error, to decide whether processing should proceed after the error.
 */
- (void) fileManager: (NSFileManager*)fileManager
     willProcessPath: (NSString*)path;
@end


@interface NSDirectoryEnumerator : NSEnumerator
{
@private
  void *_stack; /* GSIArray */
  NSString *_topPath;
  NSString *_currentFilePath;
  NSFileManager *_mgr;
  struct 
  {
    BOOL isRecursive: 1;
    BOOL isFollowing: 1;
    BOOL justContents: 1;
  } _flags;
}
- (NSDictionary*) directoryAttributes;
- (NSDictionary*) fileAttributes;
- (void) skipDescendents;

@end /* NSDirectoryEnumerator */

/* File Attributes */
/** File attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileAppendOnly;
/** File attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileCreationDate;
/** File attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileDeviceIdentifier;
/** File attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileExtensionHidden;
/** File attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileGroupOwnerAccountID;
/** File attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileGroupOwnerAccountName;
/** File attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileHFSCreatorCode;
/** File attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileHFSTypeCode;
/** File attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileImmutable;
/** File attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileModificationDate;
/** File attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileOwnerAccountID;
/** File attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileOwnerAccountName;
/** File attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFilePosixPermissions;
/** File attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileReferenceCount;
/** File attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileSize;
/** File attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileSystemFileNumber;
/** File attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileSystemNumber;
/** File attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileType;

/* File Types */

/** Possible value for '<code>NSFileType</code>' key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileTypeDirectory;
/** Possible value for '<code>NSFileType</code>' key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileTypeRegular;
/** Possible value for '<code>NSFileType</code>' key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileTypeSymbolicLink;
/** Possible value for '<code>NSFileType</code>' key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileTypeSocket;
/** Possible value for '<code>NSFileType</code>' key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileTypeFifo;
/** Possible value for '<code>NSFileType</code>' key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileTypeCharacterSpecial;
/** Possible value for '<code>NSFileType</code>' key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileTypeBlockSpecial;
/** Possible value for '<code>NSFileType</code>' key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileTypeUnknown;

/* FileSystem Attributes */

/** File system attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileSystemSize;
/** File system attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileSystemFreeSize;
/** File system attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileSystemNodes;
/** File system attribute key in dictionary returned by
    [NSFileManager-fileAttributesAtPath:traverseLink:]. */
GS_EXPORT NSString* const NSFileSystemFreeNodes;

/* Easy access to attributes in a dictionary */

@interface NSDictionary(NSFileAttributes)
- (NSDate*) fileCreationDate;
- (BOOL) fileExtensionHidden;
- (int) fileHFSCreatorCode;
- (int) fileHFSTypeCode;
- (BOOL) fileIsAppendOnly;
- (BOOL) fileIsImmutable;
- (unsigned long long) fileSize;
- (NSString*) fileType;
- (unsigned long) fileOwnerAccountID;
- (NSString*) fileOwnerAccountName;
- (unsigned long) fileGroupOwnerAccountID;
- (NSString*) fileGroupOwnerAccountName;
- (NSDate*) fileModificationDate;
- (unsigned long) filePosixPermissions;
- (unsigned long) fileSystemNumber;
- (unsigned long) fileSystemFileNumber;
@end

#endif
#endif /* __NSFileManager_h_GNUSTEP_BASE_INCLUDE */
