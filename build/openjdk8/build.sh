#!/usr/bin/bash
#
# {{{ CDDL HEADER
#
# This file and its contents are supplied under the terms of the
# Common Development and Distribution License ("CDDL"), version 1.0.
# You may only use this file in accordance with the terms of version
# 1.0 of the CDDL.
#
# A full copy of the text of the CDDL should have accompanied this
# source. A copy of the CDDL is also available via the Internet at
# http://www.illumos.org/license/CDDL.
# }}}
#
# Copyright 2019 OmniOS Community Edition (OmniOSce) Association.
#
. ../../lib/functions.sh

PROG=openjdk
VER=1.8
UPDATE=232
BUILD=09
PKG=openjdk    ##IGNORE## - filled in later
SUMMARY="tbc"; DESC="tbc"

BUILD_DEPENDS_IPS="
    system/header/header-audio
    developer/java/openjdk8
    ooce/library/fontconfig
    ooce/library/freetype2
    ooce/print/cups
"

MVER=${VER##*.}
VERHUMAN=jdk${MVER}u${UPDATE}-b$BUILD
IVER=${VER}.0

IROOT=usr/jdk/instances
IFULL=$IROOT/$PROG$IVER

OOCEPREFIX=/opt/ooce

XFORM_ARGS="
    -D VER=$VER
    -D IVER=$IVER
    -D IROOT=$IROOT
    -D IFULL=$IFULL
"

set_builddir "$PROG-jdk${MVER}u-$VERHUMAN.1"
set_arch 64
MJOBS=8

# Do these steps early to set up TMPDIR
init
download_source $PROG $VERHUMAN.1
patch_source

# The JDK build framework does not use the -j option to make.
NO_PARALLEL_MAKE=1
OUT_OF_TREE_BUILD=1
prep_build

CONFIGURE_OPTS="
    --with-milestone=fcs
    --with-user-release-suffix=omnios-$RELVER
    --with-update-version=$UPDATE
    --with-build-number=$BUILD
    --with-toolchain-type=gcc
    --with-boot-jdk=/usr/java
    --disable-headful
    --without-x
    --enable-unlimited-crypto
    --with-cacerts-file=/etc/ssl/java/cacerts
    --with-zlib=system
    --with-giflib=bundled
    --with-cups-include=$OOCEPREFIX/include
    --x-includes=$TMPDIR/openwin/X11/include
    --enable-freetype-bundling
    --with-memory-size=768
    --disable-precompiled-headers
    --disable-ccache
    --with-freetype=$OOCEPREFIX
    --with-freetype-include=$OOCEPREFIX/include/freetype2
    --with-freetype-lib=$OOCEPREFIX/lib/$ISAPART64
    --with-fontconfig=$OOCEPREFIX
    --with-fontconfig-include=$OOCEPREFIX/include
    --with-jobs=$MJOBS
"
CONFIGURE_OPTS_WS="
    --with-extra-cflags=\"-std=gnu89 -std=gnu++98 -fno-lifetime-dse\"
    --with-extra-cxxflags=\"-std=gnu++98\"
"

MAKE_ARGS="
    images
    JOBS=$MJOBS
    AS=/bin/gas
    USE_GCC=1
    BUILD_HEADLESS_ONLY=1
    FULL_DEBUG_SYMBOLS=0
    ENABLE_FULL_DEBUG_SYMBOLS=0
    NO_DOCS=1
"

export PATH=/usr/gnu/bin:$PATH

grab() {
    typeset arc=$1
    typeset dir=$2
    pushd $TMPDIR >/dev/null || logerr "pushd $TMPDIR failed"
    if [ ! -d $dir/include ]; then
        logcmd get_resource $arc || logerr "--- Failed to download $arc"
        logcmd extract_archive `basename $arc` \
            || logerr "--- Failed to extract $arc"
    fi
    popd >/dev/null
}

# Some files are present in both the j2re and j2sdk images.
# Generate a list of those files so that we deliver them in j2re only.
find_dups() {
    logmsg "Generating list of duplicate files in the JRE and SDK" >/dev/stderr

    pushd $TMPDIR/$BUILDDIR/images >/dev/null || logerr "pushd"
    for c in j2re j2sdk; do
        find $c-image -type f -o -type l | cut -d/ -f2- | sort \
            > $TMPDIR/$c.files
    done
    comm -12 $TMPDIR/j2re.files $TMPDIR/j2sdk.files > $TMPDIR/dups.files
    popd >/dev/null
    wc -l < $TMPDIR/dups.files
}

make_install_j2re() {
    J2RE_INSTALLTMP=$DESTDIR/jre

    logmsg "Installing JRE to $J2RE_INSTALLTMP"

    # copy in our JRE files
    pushd $TMPDIR/$BUILDDIR/images/j2re-image > /dev/null || logerr "pushd"
    logcmd mkdir -p $J2RE_INSTALLTMP/$IFULL
    find . | cpio -pmud $J2RE_INSTALLTMP/$IFULL
    popd > /dev/null
}

make_install_j2sdk() {
    J2SDK_INSTALLTMP=$DESTDIR/jdk
    JAVA_INSTALL_ROOT=$J2SDK_INSTALLTMP/usr/java

    logmsg "Installing SDK to $J2SDK_INSTALLTMP"

    # copy in our SDK files
    pushd $TMPDIR/$BUILDDIR/images/j2sdk-image > /dev/null || logerr "pushd"
    logcmd mkdir -p $J2SDK_INSTALLTMP/$IFULL
    find . | cpio -pmud $J2SDK_INSTALLTMP/$IFULL
    popd > /dev/null

    # Remove files which are also shipped as part of the JRE
    typeset -i num=`find_dups`
    logmsg "-- Pruning $num duplicates"
    pushd $J2SDK_INSTALLTMP/$IFULL > /dev/null || logerr "pushd"
    cat $TMPDIR/dups.files | xargs rm -f
    popd > /dev/null
}

make_install() {
    make_install_j2re
    make_install_j2sdk
}

#############################################################################

grab Xstuff/openwin.tar.gz openwin/X11/include
chmod +x $CONFIGURE_CMD
build

#############################################################################
# Build packages

VER=$IVER.$UPDATE.$BUILD
_DESC="Open-source implementation of the eighth edition of the Java SE Platform"

#############################################################################
# JRE package

# Need to keep the literal '8' here as the testsuite extracts from PKG=
PKG=runtime/java/openjdk8
PKGE=`url_encode $PKG`
SUMMARY="openjdk ${VER#*.} JRE"
DESC="$_DESC, runtime environment (JRE)"
DESTDIR=$J2RE_INSTALLTMP
make_package jre.mog jrefinal.mog

#############################################################################
# JDK package

# Need to keep the literal '8' here as the testsuite extracts from PKG=
PKG=developer/java/openjdk8
PKGE=`url_encode $PKG`
SUMMARY="openjdk ${VER#*.} JDK"
DESC="$_DESC, development kit (JDK)"
RUN_DEPENDS_IPS=runtime/java/openjdk$MVER
DESTDIR=$J2SDK_INSTALLTMP
make_package jdk.mog

# Vim hints
# vim:ts=4:sw=4:et:fdm=marker
