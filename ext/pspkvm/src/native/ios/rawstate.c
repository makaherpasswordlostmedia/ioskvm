#include <kni.h>
#include <sni.h>
#include <midpError.h>
#include <midpUtilKni.h>
#include <commonKNIMacros.h>
#include <string.h>

/* Storage points the key-sampling thread drops lx/ly values in on every
 * sample -- see javacall/implementation/ios_arm/midp/keypress.c.
 * On iOS they come from the on-screen analog stick (or a MFi/GameController pad). */
unsigned char ext_pspkvm_rawstate_lx = 128;
unsigned char ext_pspkvm_rawstate_ly = 128;

KNIEXPORT KNI_RETURNTYPE_INT
KNIDECL(com_pspkvm_keypad_RawState_getAnalogX) {
	KNI_ReturnInt((int)ext_pspkvm_rawstate_lx); }

KNIEXPORT KNI_RETURNTYPE_INT
KNIDECL(com_pspkvm_keypad_RawState_getAnalogY) {
	KNI_ReturnInt((int)ext_pspkvm_rawstate_ly); }
