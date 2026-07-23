AC_PREREQ([2.69])
AC_INIT([lvbs], [0.1], [snambakam@microsoft.com])
AM_INIT_AUTOMAKE([-Wall -Werror foreign subdir-objects])
AC_CONFIG_HEADERS([include/config.h])
AC_CONFIG_MACRO_DIR([m4])

# Checks for programs
AC_PROG_CC
AC_PROG_INSTALL
AC_PROG_LIBTOOL

# Check for ioctl headers
AC_CHECK_HEADERS([limits.h errno.h])
AC_CHECK_HEADERS([stdint.h string.h stdio.h])
AC_CHECK_HEADERS([unistd.h sys/ioctl.h ioctl.h fcntl.h])
AC_CHECK_HEADERS([sys/mman.h])
AC_CHECK_HEADERS([linux/kvm.h])

# Jansson

AC_ARG_WITH([jansson],
    [AC_HELP_STRING([--with-jansson=<dir>],
                    [use jansson binaries rooted at prefix <dir>])],
    [
        JANSSON_BASE_PATH="$withval"
    ],
    [
        JANSSON_BASE_PATH="/usr"
    ])

JANSSON_INCLUDES="-I$JANSSON_BASE_PATH/include"
JANSSON_LDFLAGS="-L$JANSSON_BASE_PATH/lib"

AC_CHECK_HEADERS(jansson.h)
AC_SUBST(JANSSON_BASE_PATH)
AC_SUBST(JANSSON_INCLUDES)
AC_SUBST(JANSSON_LDFLAGS)

AC_CHECK_LIB([jansson],
    [json_object],
    [JANSSON_LIBS="-ljansson"],
    [],
    [$JANSSON_LDFLAGS])

# Configure output
AC_CONFIG_FILES([
    Makefile
    src/Makefile
    src/loader/Makefile
    src/cli/Makefile
])
AC_OUTPUT
