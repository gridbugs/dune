#!/usr/bin/env bash

COMPILER_VERSION=5.2.1
pushd $(mktemp -d)
opam source ocaml-base-compiler.COMPILER_VERSION
opam source flexdll.0.43

# apply a patch to flexdll to work around an issue between flexdll and the x86_64-w64-mingw32 toolchain
cd flexdll.0.43
curl -fsSL https://github.com/user-attachments/files/17988298/flexdll.0.43-winres-remove-prefix.patch | patch -p1
cd ..

winpath() {
  echo $1 | sed 's/^\/c/C:/'
}

# configure and build the compiler
cd ocaml-base-compiler.COMPILER_VERSION
# Set this to the hash of the ocaml-base-compiler.pkg file in your lockdir. Find this out by trying to build the compiler package with dune and watch the verbose output.
DUNE_TOOLCHAIN_HASH=ec2fb9e295c43061b4ea55894f8a2d08
TARGET=x86_64-w64-mingw32
./configure --host=$TARGET --build=$TARGET --target=$TARGET --enable-imprecise-c99-float-ops --prefix=$(winpath $HOME/AppData/Local/Microsoft/Windows/INetCache/dune/toolchains/ocaml-base-compiler.COMPILER_VERSION-$DUNE_TOOLCHAIN_HASH/target) --docdir=$(winpath $HOME/AppData/Local/Microsoft/Windows/INetCache/dune/toolchains/ocaml-base-compiler.COMPILER_VERSION-$DUNE_TOOLCHAIN_HASH/target/doc/ocaml) --with-flexdll=$(realpath $(pwd)/../flexdll.0.43) -C
make -j
make install
