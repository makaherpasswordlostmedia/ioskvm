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


#ifdef __cplusplus
extern "C" {
#endif

#include "javacall_multimedia.h" 

/**
 * Java MMAPI call this function to create native media handler.
 * This function is called at the first time to initialize native library.
 * You can do your own initializatio job from this function.
 * 
 * @param playerId      Unique player object ID for this playing
 * @param mediaType     Media content type
 * @param fileName      File name to play (device's native path format)
 * @return              Handle of native library. if fail return NULL.
 */
javacall_handle javacall_media_create2(int playerId, javacall_media_type mediaType, const char* fileName) {
    return 0;
}

/**
 * Get supported meta data key counts for specefic media type
 * 
 * @param mediaType [in]    Media type
 * @param keyCounts [out]   Return meta data key string counts
 * 
 * @retval JAVACALL_OK              Success
 * @retval JAVACALL_FAIL            Fail
 * @retval JAVACALL_NOT_IMPLEMENTED MetaDataControl is not implemented for this media type
 */
javacall_result javacall_media_get_metadata_key_counts(javacall_handle handle, /*OUT*/ long* keyCounts) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Get meta data key strings by using media type and index value
 * 
 * @param mediaType [in]    Media type
 * @param index     [in]    Meta data key string's index value. from 0 to 'key counts - 1'.
 * @param bufLength [in]    keyBuf buffer's size in bytes. 
 * @param keyBuf    [out]   Buffer that used to return key strings. 
 *                          NULL value should be appended to the end of string.
 * 
 * @retval JAVACALL_OK              Success
 * @retval JAVACALL_OUT_OF_MEMORY     keyBuf size is too small
 * @retval JAVACALL_NOT_IMPLEMENTED  MetaDataControl is not implemented for this media type
 * @retval JAVACALL_FAIL            Fail
 */
javacall_result javacall_media_get_metadata_key(javacall_handle handle, 
                                                long index, long bufLength, 
                                                /*OUT*/ char* keyBuf) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Get meta data value strings by using meta data key string
 * 
 * @param hLIB      [in]    Handle to the library 
 * @param key       [in]    Meta data key string
 * @param bufLength [in]    dataBuf buffer's size in bytes. 
 * @param dataBuf   [out]   Buffer that used to return meta data strings. 
 *                          NULL value should be appended to the end of string.
 * 
 * @retval JAVACALL_OK              Success
 * @retval JAVACALL_OUT_OF_MEMORY     dataBuf size is too small
 * @retval JAVACALL_NOT_IMPLEMENTED  MetaDataControl is not implemented for this media type
 * @retval JAVACALL_FAIL            Fail
 */
javacall_result javacall_media_get_metadata(javacall_handle handle, 
                                            const char* key, long bufLength, 
                                            /*OUT*/ char* dataBuf) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Get volume for the given channel. 
 * The return value is independent of the master volume, which is set and retrieved with VolumeControl.
 * 
 * @param handle    Handle to the library 
 * @param channel   0-15
 * @param volume    channel volume, 0-127, or -1 if not known
 * 
 * @retval JAVACALL_OK      Success
 * @retval JAVACALL_FAIL    Fail
 */
javacall_result javacall_media_get_channel_volume(javacall_handle handle, 
                                                  long channel, /*OUT*/ long* volume) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Set volume for the given channel. To mute, set to 0. 
 * This sets the current volume for the channel and may be overwritten during playback by events in a MIDI sequence.
 * 
 * @param handle    Handle to the library 
 * @param channel   0-15
 * @param volume    channel volume, 0-127
 * 
 * @retval JAVACALL_OK      Success
 * @retval JAVACALL_FAIL    Fail
 */
javacall_result javacall_media_set_channel_volume(javacall_handle handle, 
                                                  long channel, long volume) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Set program of a channel. 
 * This sets the current program for the channel and may be overwritten during playback by events in a MIDI sequence.
 * 
 * @param handle    Handle to the library 
 * @param channel   0-15
 * @param bank      0-16383, or -1 for default bank
 * @param program   0-127
 * 
 * @retval JAVACALL_OK      Success
 * @retval JAVACALL_FAIL    Fail
 */
javacall_result javacall_media_set_program(javacall_handle handle, 
                                           long channel, long bank, long program) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Sends a short MIDI event to the device.
 * 
 * @param handle    Handle to the library 
 * @param type      0x80..0xFF, excluding 0xF0 and 0xF7, which are reserved for system exclusive
 * @param data1     for 2 and 3-byte events: first data byte, 0..127
 * @param data2     for 3-byte events: second data byte, 0..127
 * 
 * @retval JAVACALL_OK      Success
 * @retval JAVACALL_FAIL    Fail
 */
javacall_result javacall_media_short_midi_event(javacall_handle handle,
                                                long type, long data1, long data2) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Sends a long MIDI event to the device, typically a system exclusive message.
 * 
 * @param handle    Handle to the library 
 * @param data      array of the bytes to send. 
 *                  This memory buffer will be freed after this function returned.
 *                  So, you should copy this data to the other internal memory buffer
 *                  if this function needs data after return.
 * @param offset    start offset in data array
 * @param length    number of bytes to be sent
 * 
 * @retval JAVACALL_OK      Success
 * @retval JAVACALL_FAIL    Fail
 */
javacall_result javacall_media_long_midi_event(javacall_handle handle,
                                               const char* data, long offset, /*INOUT*/ long* length) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/** 
 * Get media's current playing tempo.
 * 
 * @param hLIB [in]     Handle to the library
 * @param tempo [out]   Current playing tempo
 * 
 * @retval JAVACALL_OK          Success
 * @retval JAVACALL_FAIL        Fail
 */
javacall_result javacall_media_get_tempo(javacall_handle handle, /*OUT*/ long* tempo) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Set media's current playing tempo
 * 
 * @param hLIB [in]     Handle to the library
 * @param tempo [in]    Tempo to set
 * 
 * @retval JAVACALL_OK          Success
 * @retval JAVACALL_FAIL        Fail
 */
javacall_result javacall_media_set_tempo(javacall_handle handle, long tempo) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/******************************************************************************/

/**
 * Gets the maximum playback pitch raise supported by the Player
 * 
 * @param handle    Handle to the library 
 * @param maxPitch  The maximum pitch raise in "milli-semitones".
 * 
 * @retval JAVACALL_OK      Success
 * @retval JAVACALL_FAIL    Fail
 */
javacall_result javacall_media_get_max_pitch(javacall_handle handle, /*OUT*/ long* maxPitch) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Gets the minimum playback pitch raise supported by the Player
 * 
 * @param handle    Handle to the library 
 * @param minPitch  The minimum pitch raise in "milli-semitones"
 * 
 * @retval JAVACALL_OK      Success
 * @retval JAVACALL_FAIL    Fail
 */
javacall_result javacall_media_get_min_pitch(javacall_handle handle, /*OUT*/ long* minPitch) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Set media's current playing rate
 * 
 * @param handle    Handle to the library 
 * @param pitch     The number of semi tones to raise the playback pitch. It is specified in "milli-semitones"
 * 
 * @retval JAVACALL_OK      Success
 * @retval JAVACALL_FAIL    Fail
 */
javacall_result javacall_media_set_pitch(javacall_handle handle, long pitch) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Get media's current playing rate
 * 
 * @param handle    Handle to the library 
 * @param pitch     The current playback pitch raise in "milli-semitones"
 * 
 * @retval JAVACALL_OK          Success
 * @retval JAVACALL_FAIL        Fail
 */
javacall_result javacall_media_get_pitch(javacall_handle handle, /*OUT*/ long* pitch) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/******************************************************************************/

/**
 * Query if recording is supported based on the player's content-type
 * 
 * @param handle  Handle to the library 
 * 
 * @retval JAVACALL_OK          Success
 * @retval JAVACALL_FAIL        Fail
 */
javacall_result javacall_media_supports_recording(javacall_handle handle) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Is this recording transaction is handled by native layer or Java layer?
 * 
 * @param handle    Handle to the library 
 * @param locator   URL locator string for recording data (ex: file:///root/test.wav)
 * 
 * @retval JAVACALL_OK      This recording transaction will be handled by native layer
 * @retval JAVACALL_FAIL    This recording transaction should be handled by Java layer
 */
javacall_result javacall_media_recording_handled_by_native(javacall_handle handle, 
                                                           const javacall_utf16* locator,
                                                           long locatorLength) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Is javacall_media_set_recordsize_limit function is working for this player?
 * 
 * @retval JAVACALL_TRUE    Yes. Supported.
 * @retval JAVACALL_FALSE   No. Not supported.
 */
javacall_bool javacall_media_set_recordsize_limit_supported(javacall_handle handle) {
    return JAVACALL_FALSE;
}

/**
 * Specify the maximum size of the recording including any headers.
 * If a size of -1 is passed then the record size limit should be removed.
 * 
 * @param handle    Handle to the library 
 * @param size      The maximum size bytes of the recording requested as input parameter.
 *                  The supported maximum size bytes of the recording which is less than or 
 *                  equal to the requested size as output parameter.
 * 
 * @retval JAVACALL_OK          Success
 * @retval JAVACALL_FAIL        Fail
 */
javacall_result javacall_media_set_recordsize_limit(javacall_handle handle, 
                                                    /*INOUT*/ long* size) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Starts the recording. records all the data of the player ( video / audio )
 * 
 * @param handle  Handle to the library 
 * 
 * @retval JAVACALL_OK          Success
 * @retval JAVACALL_FAIL        Fail
 */
javacall_result javacall_media_start_recording(javacall_handle handle) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Pause the recording. this should enable a future call to javacall_media_start_recording. 
 * Another call to javacall_media_start_recording after pause has been called will result 
 * in recording the new data and concatanating it to the previously recorded data.
 * 
 * @param handle  Handle to the library 
 * 
 * @retval JAVACALL_OK          Success
 * @retval JAVACALL_FAIL        Fail
 */
javacall_result javacall_media_pause_recording(javacall_handle handle) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Stop the recording.
 * 
 * @param handle  Handle to the library 
 * 
 * @retval JAVACALL_OK          Success
 * @retval JAVACALL_FAIL        Fail
 */
javacall_result javacall_media_stop_recording(javacall_handle handle) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * The recording that has been done so far should be discarded. (deleted)
 * Recording will be paused before this method is called. 
 * If javacall_media_start_recording is called after this method is called, recording should resume.
 * Calling reset after javacall_media_finish_recording will have no effect on the current recording.
 * If the Player that is associated with this RecordControl is closed, 
 * javacall_media_reset_recording will be called implicitly. 
 * 
 * @param handle  Handle to the library 
 * 
 * @retval JAVACALL_OK          Success
 * @retval JAVACALL_FAIL        Fail
 */
javacall_result javacall_media_reset_recording(javacall_handle handle) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * The recording should be completed; 
 * this may involve updating the header,flushing buffers and closing the temporary file if it is used
 * by the implementation.
 * javacall_media_pause_recording will be called before this method is called.
 * 
 * @param handle  Handle to the library 
 * 
 * @retval JAVACALL_OK          Success
 * @retval JAVACALL_FAIL        Fail
 */
javacall_result javacall_media_commit_recording(javacall_handle handle) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Get how much data was returned. 
 * This function can be called after a successful call to javacall_media_finish_recording.
 * 
 * @param handle    Handle to the library 
 * @param size      How much data was recorded
 * 
 * @retval JAVACALL_OK          Success
 * @retval JAVACALL_FAIL        Fail
 */
javacall_result javacall_media_get_recorded_data_size(javacall_handle handle, 
                                                      /*OUT*/ long* size) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Gets the recorded data.
 * This function can be called after a successful call to javacall_media_finish_recording.
 * It receives the data recorded from offset till the size.
 * 
 * @param handle    Handle to the library 
 * @param buffer    Buffer will contains the recorded data
 * @param offset    An offset to the start of the required recorded data
 * @param size      How much data will be copied to buffer
 * 
 * @retval JAVACALL_OK          Success
 * @retval JAVACALL_FAIL        Fail
 */
javacall_result javacall_media_get_recorded_data(javacall_handle handle, 
                                                 /*OUT*/ char* buffer, long offset, long size) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Get the current recording data content type mime string length
 *
 * @return  If success return length of string else return 0
 */
int javacall_media_get_record_content_type_length(javacall_handle handle) {
    return 0;
}

/**
 * Get the current recording data content type mime string length
 * For example : 'audio/x-wav' for audio recording
 *
 * @param handle                Handle of native player
 * @param contentTypeBuf        Buffer to return content type unicode string
 * @param contentTypeBufLength  Lenght of contentTypeBuf buffer (in unicode metrics)
 *
 * @return  Length of content type string stored in contentTypeBuf
 */
int javacall_media_get_record_content_type(javacall_handle handle, 
                                           /*OUT*/ javacall_utf16* contentTypeBuf,
                                           int contentTypeBufLength) {
    return 0;
}

/**
 * Close the recording. Delete all resources related with this recording.
 * 
 * @param handle    Handle to the library 
 * 
 * @retval JAVACALL_OK      Success
 * @retval JAVACALL_FAIL    Fail
 */
javacall_result javacall_media_close_recording(javacall_handle handle) {
    return JAVACALL_NOT_IMPLEMENTED;
}


/**
 * This function is used to ascertain the availability of MIDI bank support
 *
 * @param handle     Handle to the native player
 * @param supported  return of support availability
 *
 * @retval JAVACALL_OK      MIDI Bank Query support is available
 * @retval JAVACALL_FAIL    NO MIDI Bank Query support is available
 */
javacall_result javacall_media_is_midibank_query_supported(javacall_handle handle,
                                             long* supported) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * This function is used to get a list of installed banks. If the custom
 * parameter is true, a list of custom banks is returned. Otherwise, a list of
 * all banks (custom and internal) is returned. This function can be left empty.
 *
 * @param handle    Handle to the native player
 * @param custom    a flag indicating whether to return just custom banks, or
 *                  all banks.
 * @param banklist  an array which will be filled out with the banklist
 * @param numlist   the length of the array to be filled out, and on return
 *                  contains the number of values written to the array.
 *
 * @retval JAVACALL_OK      Bank List is available
 * @retval JAVACALL_FAIL    Bank List is NOT available
 */
javacall_result javacall_media_get_midibank_list(javacall_handle handle,
                                             long custom,
                                             /*OUT*/short* banklist,
                                             /*INOUT*/long* numlist) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Given a bank, program and key, get name of key. This function applies to
 * key-mapped banks (i.e. percussive banks or effect banks) only. If the returned
 * keyname length is 0, then the key is not mapped to a sound. For melodic banks,
 * where each key (=note) produces the same sound at different pitch, this
 * function always returns a 0 length string. For space saving reasons an
 * implementation may return a 0 length string instead of the keyname. This
 * can be left empty.
 *
 * @param handle    Handle to the native player
 * @param bank      The bank to query
 * @param program   The program to query
 * @param key       The key to query
 * @param keyname   The name of the key returned.
 * @param keynameLen    The length of the keyname array, and on return the
 *                      length of the keyname.
 *
 * @retval JAVACALL_OK      Keyname available
 * @retval JAVACALL_FAIL    Keyname not supported
 */
javacall_result javacall_media_get_midibank_key_name(javacall_handle handle,
                                            long bank,
                                            long program,
                                            long key,
                                            /*OUT*/char* keyname,
                                            /*INOUT*/long* keynameLen) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Given the bank and program, get name of program. For space-saving reasons
 * a 0 length string may be returned.
 *
 * @param handle    Handle to the native player
 * @param bank      The bank being queried
 * @param program   The program being queried
 * @param progname  The name of the program returned
 * @param prognameLen    The length of the progname array, and on return the
 *                       length of the progname
 *
 * @retval JAVACALL_OK      Program name available
 * @retval JAVACALL_FAIL    Program name not supported
 */
javacall_result javacall_media_get_midibank_program_name(javacall_handle handle,
                                                long bank,
                                                long program,
                                                /*OUT*/char* progname,
                                                /*INOUT*/long* prognameLen) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Given bank, get list of program numbers. If and only if this bank is not
 * installed, an empty array is returned.
 *
 * @param handle    Handle to the native player
 * @param bank      The bank being queried
 * @param proglist  The Program List being returned
 * @param proglistLen     The length of the proglist, and on return the number
 *                        of program numbers in the list
 *
 * @retval JAVACALL_OK     Program list available
 * @retval JAVACALL_FAIL   Program list unsupported
 */
javacall_result javacall_media_get_midibank_program_list(javacall_handle handle,
                                                long bank,
                                                /*OUT*/char* proglist,
                                                /*INOUT*/long* proglistLen) {
    return JAVACALL_NOT_IMPLEMENTED;
}

/**
 * Returns the program assigned to the channel. It represents the current state
 * of the channel. During playbank of the MIDI file, the program may change due
 * to program change events in the MIDI file. The returned array is represented
 * by an array {bank, program}. The support of this function is optional.
 *
 * @param handle    Handle to the native player
 * @param channel   The channel being queried
 * @param prog      The return array (size 2) in the form {bank, program}
 *
 * @retval JAVACALL_OK    Program available
 * @retval JAVACALL_FAIL  Get Program unsupported
 */
javacall_result javacall_media_get_midibank_program(javacall_handle handle,
                                                long channel,
                                                /*OUT*/long* prog) {
    return JAVACALL_NOT_IMPLEMENTED;
}

#ifdef __cplusplus
}
#endif 
 
