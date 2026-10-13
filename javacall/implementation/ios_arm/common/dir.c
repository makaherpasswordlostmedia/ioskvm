/*
 *
 * Copyright  1990-2007 Sun Microsystems, Inc. All Rights Reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER
 * 
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License version
 * 2 only, as published by the Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License version 2 for more details (a copy is
 * included at /legal/license.txt).
 * 
 * You should have received a copy of the GNU General Public License
 * version 2 along with this work; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
 * 02110-1301 USA
 * 
 * Please contact Sun Microsystems, Inc., 4150 Network Circle, Santa
 * Clara, CA 95054 or visit www.sun.com if you need additional
 * information or have any questions.
 */

/**
 * @file
 * iOS (Darwin/POSIX) implementation of javacall_dir.
 * The host app chdir()s into its sandbox Documents/pspkvm directory
 * before the VM starts, so the Java root is simply ".".
 */

#ifdef __cplusplus
extern "C" {
#endif

#include "javacall_dir.h"
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/param.h>
#include <sys/statvfs.h>
#include <stdio.h>
#include <unistd.h>

extern char* javacall_UNICODEsToUtf8(const javacall_utf16* fileName, int fileNameLen);

typedef struct {
    DIR* d;
    char path[JAVACALL_MAX_FILE_NAME_LENGTH + 1];
} dir_slot;

javacall_handle javacall_dir_open(const javacall_utf16* path, int pathLen) {
    char* szPath = javacall_UNICODEsToUtf8(path, pathLen);
    dir_slot* s;
    if (!szPath) {
        return NULL;
    }
    s = (dir_slot*)malloc(sizeof(dir_slot));
    if (!s) {
        return NULL;
    }
    s->d = opendir(szPath);
    if (!s->d) {
        free(s);
        return NULL;
    }
    strncpy(s->path, szPath, JAVACALL_MAX_FILE_NAME_LENGTH);
    s->path[JAVACALL_MAX_FILE_NAME_LENGTH] = 0;
    return (javacall_handle)s;
}

void javacall_dir_close(javacall_handle handle) {
    dir_slot* s = (dir_slot*)handle;
    if (s) {
        if (s->d) closedir(s->d);
        free(s);
    }
}

javacall_utf16* javacall_dir_get_next(javacall_handle handle, int* /*OUT*/ outFilenameLength) {
    static javacall_utf16 name[JAVACALL_MAX_FILE_NAME_LENGTH + 2];
    dir_slot* s = (dir_slot*)handle;
    struct dirent* d;
    struct stat st;
    char full[JAVACALL_MAX_FILE_NAME_LENGTH * 2 + 2];
    int len, isdir = 0;

    if (!s || !s->d) return NULL;
    d = readdir(s->d);
    if (!d) return NULL;

    len = (int)strlen(d->d_name);
    if (len >= JAVACALL_MAX_FILE_NAME_LENGTH - 1) {
        return NULL;
    }

    if (d->d_type == DT_DIR) {
        isdir = 1;
    } else if (d->d_type == DT_UNKNOWN || d->d_type == DT_LNK) {
        snprintf(full, sizeof(full), "%s/%s", s->path, d->d_name);
        if (stat(full, &st) == 0 && S_ISDIR(st.st_mode)) isdir = 1;
    }

    /* names are treated as Latin-1 like the PSP port; decode UTF-8 properly */
    {
        const unsigned char* p = (const unsigned char*)d->d_name;
        int o = 0;
        while (*p && o < JAVACALL_MAX_FILE_NAME_LENGTH - 1) {
            unsigned int c = *p++;
            if (c < 0x80) {
                name[o++] = (javacall_utf16)c;
            } else if ((c & 0xE0) == 0xC0 && (p[0] & 0xC0) == 0x80) {
                name[o++] = (javacall_utf16)(((c & 0x1F) << 6) | (p[0] & 0x3F));
                p += 1;
            } else if ((c & 0xF0) == 0xE0 && (p[0] & 0xC0) == 0x80 && (p[1] & 0xC0) == 0x80) {
                name[o++] = (javacall_utf16)(((c & 0x0F) << 12) | ((p[0] & 0x3F) << 6) | (p[1] & 0x3F));
                p += 2;
            } else {
                name[o++] = (javacall_utf16)'?';
            }
        }
        len = o;
    }
    if (isdir) {
        name[len++] = (javacall_utf16)'/';
    }
    name[len] = 0;
    *outFilenameLength = len;
    return name;
}

javacall_int64 javacall_dir_get_free_space_for_java(void) {
    struct statvfs sf;
    if (statvfs(".", &sf) == 0) {
        return (javacall_int64)sf.f_bavail * (javacall_int64)sf.f_frsize;
    }
    return 0;
}

javacall_result javacall_dir_get_root_path(javacall_utf16* /* OUT */ rootPath,
                                           int* /* IN | OUT */ rootPathLen) {
    static const char* root = ".";
    int i, len = (int)strlen(root);
    if (*rootPathLen < len) {
        return JAVACALL_FAIL;
    }
    for (i = 0; i < len; i++) {
        rootPath[i] = (javacall_utf16)root[i];
    }
    *rootPathLen = len;
    return JAVACALL_OK;
}

javacall_utf16 javacall_get_file_separator(void) {
    return '/';
}

javacall_bool javacall_dir_is_secure_storage(javacall_utf16* classPath, int pathLen) {
    return JAVACALL_FALSE;
}

#ifdef __cplusplus
}
#endif
