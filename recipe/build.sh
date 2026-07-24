#!/usr/bin/env bash
set -euxo pipefail

# Keep gdb curses/termcap-free (stub termcap, no TUI). Conda build tools drag
# ncurses into the build environment transitively, but any conda .so in the
# host binaries' NEEDED entries could not be resolved at runtime (binary prefix
# relocation is off, so baked rpaths are dead). Preset the configure caches so
# gdb behaves as on a system without curses.
export ac_cv_search_tgetent=no ac_cv_search_waddstr=no \
       ac_cv_header_curses_h=no ac_cv_header_ncurses_h=no \
       ac_cv_header_ncurses_ncurses_h=no ac_cv_header_ncurses_curses_h=no

# Host tools must depend on glibc only. Append to the conda activation's
# LDFLAGS rather than replacing them.
export LDFLAGS="${LDFLAGS:-} -static-libstdc++ -static-libgcc"

# build-baremetal-toolchain.sh takes the install location from the environment
# (there is no command-line flag for it) and configures gcc with an absolute
# --prefix="$installdir", so this installs straight into the conda build prefix
# and rattler-build records relocatable placeholders. $prefix must stay "/" so
# files land at $PREFIX/bin rather than $PREFIX/usr/bin.
export installdir="$PREFIX"
export prefix="/"
# newlib-nano is staged separately and then merged into $installdir by the
# script itself (libc.a -> libc_nano.a and friends, plus nano.specs), so this
# must be a scratch path and NOT $PREFIX.
export nano_installdir="${SRC_DIR}/nano_install"

# Call build-baremetal-toolchain.sh directly rather than through the
# build-gnu-toolchain.sh wrapper. The wrapper treats everything after "--" as
# make targets (it `break 2`s out of its option parser), so the "-- --release
# --enable-newlib-nano" form shown in Arm's README would silently pass those as
# build stage names. Going one level down makes the configuration explicit; the
# flags below reproduce what the wrapper generates for --target=arm-none-eabi
# --rmprofile, minus the Fortran frontend.
#
# --release              turns down self-consistency checking, as Arm's own
#                        release builds do
# --no-package           we want the install tree, not distribution tarballs
# --with-multilib-list   rmprofile only (Cortex-M/R). aprofile roughly doubles
#                        an already multi-hour build; see README.
# no --tag               Arm asks that their release branding not be reused
"${SRC_DIR}/src/gnu-devtools-for-arm/build-baremetal-toolchain.sh" \
  --target=arm-none-eabi \
  --srcdir="${SRC_DIR}/src" \
  --builddir="${SRC_DIR}/build-arm-none-eabi" \
  -j "${CPU_COUNT}" \
  --release \
  --no-package \
  --enable-newlib-nano \
  --disable-qemu \
  --no-check-gdb \
  --config-flags-gcc=--with-multilib-list=rmprofile \
  --bugurl="https://github.com/EliaCereda/gcc-arm-none-eabi/issues"

# Strip host binaries before packaging. Target libraries (newlib .a) must keep
# their symbols — only bin/ and libexec/. STRIP is the conda binutils' host
# strip from the compiler activation.
find "$PREFIX"/bin "$PREFIX"/libexec -type f | xargs -r "${STRIP:-strip}" -- 2>/dev/null || true
find "$PREFIX" -name '*.la' -delete

# The release build generates the full texinfo/man documentation set; drop it
# to keep the package a sane size.
rm -rf "$PREFIX"/share/info "$PREFIX"/share/doc "$PREFIX"/share/man
