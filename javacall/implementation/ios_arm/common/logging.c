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

#include "javacall_logging.h"
#include <stdio.h>
#include <string.h>
#include <stdarg.h>
#include <pthread.h>

#ifdef __cplusplus
extern "C" {
#endif

/* implemented by the iOS host (ios/KVMLog.m) - may be NULL-safe */
extern void pspkvm_ios_log(const char* s);

static int log_channel_consle = 0;
static int log_channel_startup = 0;
static int log_channel_stdout = 1;   /* default ON: NSLog/stderr is the only debugger on device */
static int log_channel_file = 0;

void javacall_print(const char *s) {
    if (log_channel_consle || log_channel_startup || log_channel_file) pspkvm_ios_log(s);
    if (log_channel_stdout) fputs(s, stderr);
}

void javacall_printf(const char* format, ...) {
    char buf[4096];
    va_list ap;
    va_start(ap, format);
    vsnprintf(buf, sizeof(buf), format, ap);
    va_end(ap);
    javacall_print(buf);
}

void javacall_logging_channel(int channel) {
    log_channel_consle  = (channel & JAVACALL_LOG_CHANNEL_CONSOLE) ? 1 : 0;
    log_channel_startup = (channel & JAVACALL_LOG_CHANNEL_STARTUP) ? 1 : 0;
    log_channel_stdout  = (channel & JAVACALL_LOG_CHANNEL_STDOUT)  ? 1 : 0;
    log_channel_file    = (channel & JAVACALL_LOG_CHANNEL_FILE)    ? 1 : 0;
}

#ifdef __cplusplus
}
#endif
