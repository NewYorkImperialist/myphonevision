#!/bin/bash
# Build ALVR's client library for iOS and repack it as ALVRClientCore.xcframework.
set -e
cd "$(dirname "$0")"

# Get ALVR at the pinned commit (v21.0.0-dev14) into ./ALVR
./fetch_alvr.sh

# Check if Rust is installed
if command -v rustc &> /dev/null; then
    echo "Rust is already installed."
else
    echo "Rust is not installed. Installing..."
    curl --proto '=https' --tlsv1.2 https://sh.rustup.rs -sSf | sh
fi

# Install or update cbindgen
cargo install cbindgen

# ALVR pins its Rust version (ALVR/rust-toolchain.toml); run rustup and cargo inside
# ALVR so they use it (rustup installs it on first use), and add the iOS target to it.
cd ALVR
rustup target add aarch64-apple-ios

cargo build --target=aarch64-apple-ios -p alvr_client_core --profile distribution
cd alvr/client_core
cbindgen --config cbindgen.toml --crate alvr_client_core --output ../../alvr_client_core.h
cd ../../../

sh repack_alvr_client.sh
# The Rust build cache stays in ALVR/target (git-ignored) so rebuilds are fast.
