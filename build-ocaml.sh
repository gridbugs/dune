#!/usr/bin/env bash

COMPILER_VERSION=5.2.1
FLEXDLL_VERSION=0.43
pushd $(mktemp -d)
opam source ocaml-base-compiler.$COMPILER_VERSION
opam source flexdll.$FLEXDLL_VERSION

winpath() {
  echo $1 | sed 's/^\/c/C:/'
}

# Set this to the hash of the ocaml-base-compiler.pkg file in your lockdir. Find this out by trying to build the compiler package with dune and watch the verbose output.
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
