#!/bin/sh
USAGE="`basename $0`: [-CTcdghjmnp] [-r rootdir] [-J JDK_DIR]"
HELP="Options:
-C               performs a clean before building
-c               build CLDC HI
-d               debug build
-e               erase build output / clean
-h               print this help information
-j               build javacall_impl
-m               build midp
-n              use NAMS
-p               build pcsl
-T               compile THUMB mode
-J JDK_DIR       specify the JDK directory (i.e. c:/jdk1.4)
-r rootdir       use <rootdir> as the root of the tree for building"


BUILD_TARGET=IOS_ARMV7_JAVACALL
unset DEBUG_OPTION
unset CLEAN
unset BUILD_JAVACALL_IMPL
unset BUILD_PCSL
unset BUILD_CLDC
unset ERASE_BUILD_OUTPUT
unset BUILD_MIDP
USE_NAMS=false
ENABLE_THUMB=false
USE_NOKIA_UI=true
USE_PSPKVM_EXT=true
USE_JSR_75=true
USE_JSR_179=false
USE_JSR_172=true
USE_JSR_226=true

while getopts \?J:Ccdehjmnpr: c
do
	case $c in
	C)	CLEAN="true";;
	J)	JDK_DIR=$OPTARG
		export JDK_DIR;;
	c)	BUILD_CLDC="true";;
	d)	DEBUG_OPTION="USE_DEBUG=true";;
	e)	ERASE_BUILD_OUTPUT="true";CLEAN="true";;
	h)	echo "${USAGE}"
		echo "${HELP}"
		exit 2;;
	j)	BUILD_JAVACALL_IMPL="true";;
	m)	BUILD_MIDP="true";;
	n)    USE_NAMS=true;;
	p)	BUILD_PCSL="true";;
	r)	WS_ROOT=$OPTARG;;
	\?)	echo "${USAGE}"
		echo "${HELP}"
		exit 2;;
	esac
done

# ---- iOS toolchain (override from the environment / CI) ----
: "${THEOS:?set THEOS to your Theos checkout}"
export IOS_SDK="${IOS_SDK:-$THEOS/sdks/iPhoneOS9.3.sdk}"
export IOS_MIN="${IOS_MIN:-7.0}"
TOOLBIN="$THEOS/toolchain/linux/iphone/bin"
export IOS_CC="${IOS_CC:-$TOOLBIN/clang}"
export IOS_CXX="${IOS_CXX:-$TOOLBIN/clang++}"
export IOS_AR="${IOS_AR:-$( [ -x "$TOOLBIN/llvm-ar" ] && echo "$TOOLBIN/llvm-ar" || command -v ar )}"
export IOS_FREETYPE_INC="${IOS_FREETYPE_INC:-$IOS_SDK/usr/include/freetype2}"
# Vanilla (non-Apple) clang: no -arch / -miphoneos-version-min, select the target with --target
export IOS_TARGET_FLAGS="${IOS_TARGET_FLAGS:---target=armv7-apple-ios$IOS_MIN -isysroot $IOS_SDK}"
export IOS_CFLAGS="${IOS_CFLAGS:-$IOS_TARGET_FLAGS -O2 -fno-strict-aliasing -fno-stack-protector -fno-modules -fno-implicit-modules -fno-implicit-module-maps -Wno-error -Wno-register -Wno-reserved-user-defined-literal -Wno-implicit-function-declaration -Wno-int-conversion -Wno-incompatible-function-pointer-types -I$IOS_FREETYPE_INC}"
# JDK_DIR: JDK able to emit 1.3-level class files for the CLDC preverifier (JDK 8 or older)
: "${JDK_DIR:?set JDK_DIR}"
export JDK_DIR

echo
echo
echo "-------------- BUILD ${BUILD_TARGET}----------------"

if [ -z "${WS_ROOT}" ]
then
	WS_ROOT=`pwd`
	echo WS_ROOT not specified using ${WS_ROOT}
fi

if [ -z "${BUILD_JAVACALL_IMPL}" -a -z "${BUILD_PCSL}" -a -z "${BUILD_CLDC}" -a -z "${BUILD_MIDP}" ]
then
	BUILD_JAVACALL_IMPL=true
	BUILD_PCSL=true
	BUILD_CLDC=true
	BUILD_MIDP=true
fi

JAVACALL_DIR=${WS_ROOT}/javacall
PCSL_DIR=${WS_ROOT}/pcsl
CLDC_DIR=${WS_ROOT}/cldc
MIDP_DIR=${WS_ROOT}/midp
TOOLS_DIR=${WS_ROOT}/tools
RESTRICTED_CRYPTO_DIR=${WS_ROOT}/restricted_crypto
JSR_135_DIR=${WS_ROOT}/jsr135
JPEG_DIR=${WS_ROOT}/jpeg
JSR_120_DIR=${WS_ROOT}/jsr120
JSR_75_DIR=${WS_ROOT}/jsr75
NOKIA_UI_DIR=${WS_ROOT}/ext/nokia
PSPKVM_EXT_DIR=${WS_ROOT}/ext/pspkvm
JSR_179_DIR=${WS_ROOT}/jsr179
JSR_172_DIR=${WS_ROOT}/jsr172
JSR_226_DIR=${WS_ROOT}/jsr226
PISCES_DIR=${WS_ROOT}/pisces

JAVACALL_OUTPUT_DIR=${JAVACALL_DIR}/configuration/phoneMEFeature/ios_arm/output
#JAVACALL_OUTPUT_DIR=${JAVACALL_DIR}/configuration/phoneMEFeature/cygwin_x86/output
PCSL_OUTPUT_DIR=${PCSL_DIR}/output

if [ "${BUILD_JAVACALL_IMPL}" = "true" ]
then
	BUILDMODULE=${JAVACALL_DIR}/configuration/phoneMEFeature/ios_arm
	cd ${BUILDMODULE}
	if [ "${CLEAN}" = "true" ]; then
		echo "Cleaning:    ${BUILDMODULE}"
		rm -rf ${JAVACALL_OUTPUT_DIR}
	fi
	if [ "${ERASE_BUILD_OUTPUT}" != "true" ]; then
	    echo "Building:    ${BUILDMODULE}"
		make USE_NATIVE_AMS=${USE_NAMS} \
			JAVACALL_DIR=${JAVACALL_DIR}  \
			JAVACALL_OUTPUT_DIR=${JAVACALL_OUTPUT_DIR} \
			USE_JSR_135=true \
			USE_JSR_75=${USE_JSR_75} \
			USE_JSR_179=${USE_JSR_179} \
			USE_PROPERTIES_FROM_FS=true \
			${DEBUG_OPTION}
	fi
	if [ $? != 0 ];then
			echo make failed for ${BUILD_TARGET} module ${BUILDMODULE}
			exit 1
	fi
fi

if [ "${BUILD_PCSL}" = "true" ]
then
	BUILDMODULE=${PCSL_DIR}
	cd ${BUILDMODULE}
	if [ "${CLEAN}" = "true" ]; then
		echo "Cleaning:    ${BUILDMODULE}"
		rm -rf ${PCSL_OUTPUT_DIR}
	fi
	if [ "${ERASE_BUILD_OUTPUT}" != "true" ]; then
	    echo "Building:    ${BUILDMODULE}"
		make JAVACALL_OUTPUT_DIR=${JAVACALL_OUTPUT_DIR} \
			PCSL_PLATFORM=javacall_ios_gcc \
			PCSL_OUTPUT_DIR=${PCSL_OUTPUT_DIR} \
			${DEBUG_OPTION}
	fi
	if [ $? != 0 ];then
			echo make failed for ${BUILD_TARGET} module ${BUILDMODULE}
			exit 1
	fi
fi

if [ "${BUILD_CLDC}" = "true" ]
then
	BUILDMODULE=${CLDC_DIR}/build/javacall_ios_gcc
	cd ${BUILDMODULE}
	if [ "${CLEAN}" = "true" ]; then
		echo "Cleaning:    ${BUILDMODULE}"
		rm -rf dist loopgen romgen target tools ../classes ../tmpclasses ../classes.zip
	fi
	if [ "${ERASE_BUILD_OUTPUT}" != "true" ]; then
	    echo "Building:    ${BUILDMODULE}"
		make JDK_DIR=${JDK_DIR} \
			ENABLE_ISOLATES=true \
			ENABLE_PCSL=true \
			PCSL_OUTPUT_DIR=${PCSL_OUTPUT_DIR} \
			PCSL_DIST_DIR=${PCSL_OUTPUT_DIR}/javacall_arm \
			JAVACALL_OUTPUT_DIR=${JAVACALL_OUTPUT_DIR} \
			JVMWorkSpace=${CLDC_DIR} \
			${DEBUG_OPTION}
	fi
	if [ $? != 0 ];then
			echo make failed for ${BUILD_TARGET} module ${BUILDMODULE}
			exit 1
	fi
fi

if [ "${BUILD_MIDP}" = "true" ]
then
	BUILDMODULE=${MIDP_DIR}/build/javacall_ios
	cd ${BUILDMODULE}
	if [ "${CLEAN}" = "true" ]; then
		echo "Cleaning:    ${BUILDMODULE}"
		rm -rf output
	fi
	if [ "${ERASE_BUILD_OUTPUT}" != "true" ]; then
	    echo "Building:    ${BUILDMODULE}"
		make JDK_DIR=${JDK_DIR} \
			USE_NATIVE_AMS=${USE_NAMS} \
			JAVACALL_PLATFORM=ios_arm \
			JAVACALL_OUTPUT_DIR=${JAVACALL_OUTPUT_DIR} \
			PCSL_OUTPUT_DIR=${PCSL_OUTPUT_DIR} \
			CLDC_DIST_DIR=${CLDC_DIR}/build/javacall_ios_gcc/dist \
			TOOLS_DIR=${TOOLS_DIR} \
			RESTRICTED_CRYPTO_DIR=${RESTRICTED_CRYPTO_DIR} \
			USE_MULTIPLE_ISOLATES=true \
			skip_ams_executables=true \
			JPEG_DIR=${JPEG_DIR} \
			USE_JSR_75=${USE_JSR_75} \
			JSR_75_DIR=${JSR_75_DIR} \
			JSR_135_DIR=${JSR_135_DIR} \
			JSR_120_DIR=${JSR_120_DIR} \
			USE_JSR_179=${USE_JSR_179} \
			JSR_179_DIR=${JSR_179_DIR} \
			USE_NOKIA_UI=${USE_NOKIA_UI} \
			NOKIA_UI_DIR=${NOKIA_UI_DIR} \
			USE_PSPKVM_EXT=${USE_PSPKVM_EXT} \
			PSPKVM_EXT_DIR=${PSPKVM_EXT_DIR} \
			SOFT_KEYBOARD_ENABLED=true \
			JSR_172_DIR=${JSR_172_DIR} \
			USE_JSR_172=${USE_JSR_172} \
			USE_JSR_226=${USE_JSR_226} \
			JSR_226_DIR=${JSR_226_DIR} \
			PISCES_DIR=${PISCES_DIR} \
			${DEBUG_OPTION}
		if [ $? != 0 ];then
			echo make failed for ${BUILD_TARGET} module ${BUILDMODULE}
			exit 1
		else
			echo Build phoneME libs done. Now run: make -C ios package
		fi
	fi
fi
