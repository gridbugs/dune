#!/usr/bin/env bash

# Script to build and install the compiler in a similar manner to dune
# toolchains. This can be helpful when debugging issues with dune toolchains.
# It also allows one to use dune to build a project that depends on the
# compiler when support for building the compiler with dune toolchains is
# broken or not yet implemented, as dune will see compilers installed using
# this script and be able to use them as though they had been installed with
# dune toolchains.

COMPILER_VERSION=5.2.1
FLEXDLL_VERSION=0.43
pushd $(mktemp -d)
opam source ocaml-base-compiler.$COMPILER_VERSION
opam source flexdll.$FLEXDLL_VERSION

# Convert a cygwin-style path (e.g. "/c/foo/bar") into a windows-style path
# (e.g. "C:/foo/bar"). The resulting ptah will still use slashes as delimiters
# rather than forward slashes. Only works if the path in inside the C-drive.
winpath() {
  echo $1 | sed 's/^\/c/C:/'
}

# Set this to the hash of the ocaml-base-compiler.pkg file in your lockdir.
# Find this out by trying to build the compiler package with dune and watch the
# verbose output.
DUNE_TOOLCHAIN_HASH=ec2fb9e295c43061b4ea55894f8a2d08
PREFIX=$(winpath $HOME/AppData/Local/Microsoft/Windows/INetCache/dune/toolchains/ocaml-base-compiler.$COMPILER_VERSION-$DUNE_TOOLCHAIN_HASH/target)

# configure and build the compiler
cd ocaml-base-compiler.$COMPILER_VERSION
./configure \
  --build=x86_64-w64-mingw32 \
  --enable-imprecise-c99-float-ops \
  --prefix=$PREFIX \
  --docdir=$PREFIX/doc/ocaml \
  --with-flexdll=$(realpath $(pwd)/../flexdll.$FLEXDLL_VERSION) \
  -C
make -j
make install
