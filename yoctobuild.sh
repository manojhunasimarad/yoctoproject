#!/bin/bash

set -ex

# Set variables for versions and paths
POKY_VERSION="styhead"  # Specify the version for poky
META_RPI_VERSION="master"  # Specify the version for meta-raspberrypi
META_RPI_URL="https://git.yoctoproject.org/meta-raspberrypi"
META_OE_URL="https://github.com/openembedded/meta-openembedded.git"
BUILD_DIR="$HOME/yoctoproject"
DOWNLOADS_DIR="$HOME/yoctoproject/downloads"
SSTATE_CACHE_DIR="$HOME/yoctoproject/sstate-cache"
LOCALE="en_US.UTF-8"  # Set your desired locale here

# Create build directory if it doesn't exist
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

# Set locale environment variables
export LC_ALL="$LOCALE"
export LANG="$LOCALE"
export LANGUAGE="$LOCALE"

# Check and set locale if needed (Ubuntu/Debian)
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Checking locale settings..."
    if ! locale | grep -q "$LOCALE"; then
        echo "Locale $LOCALE not found. Installing and configuring..."
        sudo apt-get install -y locales
        sudo dpkg-reconfigure locales
        sudo locale-gen "$LOCALE"
        sudo update-locale LC_ALL="$LOCALE" LANG="$LOCALE"
        echo "Locale set to $LOCALE. Please restart the terminal for changes to fully take effect."
    else
        echo "Locale $LOCALE already set."
    fi
fi

# Function to check if a directory exists and clone if it doesn't
check_and_clone() {
    local url="$1"
    local dir="$2"
    local version="$3"

    if [ ! -d "$dir" ]; then
        echo "Cloning $dir..."
        git clone "$url" "$dir"
        if [ -n "$version" ]; then
            cd "$dir"
            git checkout "$version"
            cd - > /dev/null
        fi
    else
        echo "Directory $dir already exists. Skipping clone."
        if [ -n "$version" ]; then
            echo "Checking out version $version in $dir"
            cd "$dir"
            git checkout "$version"
            cd - > /dev/null
        fi
    fi
}

# Clone the Poky repository
echo "Cloning Poky repository..."
check_and_clone "https://git.yoctoproject.org/poky.git" "poky" "$POKY_VERSION"

# Initialize the build environment after cloning poky
echo "Initializing build environment..."
rm -rf build/conf/local.conf
source poky/oe-init-build-env

# Clone necessary meta layers if they don't exist.
echo "Cloning meta layers..."
check_and_clone "$META_RPI_URL" "../meta-raspberrypi" "$META_RPI_VERSION"
check_and_clone "$META_OE_URL" "../meta-openembedded" ""  # No specific version for meta-openembedded

# Add layers to bblayers.conf dynamically based on their existence in conf/bblayers.conf
echo "Adding layers to bblayers.conf..."

# Add layers to bblayers.conf dynamically based on their existence in conf/bblayers.conf.
add_layer_to_bblayers() {
    local layer_path="$1"
    local layer_name=$(basename "$layer_path")  # Get the name of the layer from the path

    # Check if the layer is already present in bblayers.conf.
    if bitbake-layers show-layers | grep -q "${layer_name}"; then
        echo "${layer_name} is already present in bblayers.conf. Skipping addition."
    else
        echo "Adding ${layer_name} to bblayers.conf..."
        bitbake-layers add-layer "$layer_path"
    fi
}

# Add required layers for virtualization-layer dependencies.
echo "Adding required layers for virtualization-layer dependencies..."
add_layer_to_bblayers "../meta-openembedded/meta-filesystems"  # Filesystems layer dependency.
add_layer_to_bblayers "../meta-openembedded/meta-networking"   # Networking layer dependency.
add_layer_to_bblayers "../meta-openembedded/meta-python"       # Python layer dependency.
add_layer_to_bblayers "../meta-openembedded/meta-oe"           # OE layer dependency.
add_layer_to_bblayers "../meta-raspberrypi"                    # Raspberry Pi layer dependency.
add_layer_to_bblayers "../meta-virtualization"                 # Virtualization layer.

# Configure local.conf
echo "Configuring local.conf..."
cat <<EOL >> conf/local.conf
MACHINE ??= "raspberrypi3-64"
#DISTRO_FEATURES:append = " virtualization systemd"
#MACHINE_ESSENTIAL_EXTRA_RRECOMMENDS += "kernel-modules"
#VIRTUAL-RUNTIME_init_manager = "systemd"
#DISTRO_FEATURES_BACKFILL_CONSIDERED = "sysvinit"
#VIRTUAL-RUNTIME_initscripts = "systemd-compat-units"
#IMAGE_INSTALL:append = "python3 python3-pyserial python3-numpy"
ENABLE_UART = "1"
IMAGE_FSTYPES = "ext3 rpi-sdimg wic wic.bmap"
DL_DIR = "${DOWNLOADS_DIR}"
SSTATE_DIR = "${SSTATE_CACHE_DIR}"
SOURCE_MIRROR_URL ?= "file://${DOWNLOADS_DIR}/"
INHERIT += "own-mirrors"
BB_GENERATE_MIRROR_TARBALLS = "1"
# Locale settings for Yocto builds (to avoid unsupported locale errors)
#GLIBC_GENERATE_LOCALES = "${LOCALE}"
ENABLE_BINARY_LOCALE_GENERATION = "1"
CONNECTIVITY_CHECK_URIS = "https://www.google.com/"
#skip connectivity checks
CONNECTIVITY_CHECK_URIS = ""
#BB_NUMBER_THREADS="32"
EOL

# Show added layers for confirmation
echo "Current layers:"
bitbake-layers show-layers

# Fetch all sources for the specified image (optional)
#echo "Fetching all sources..."
#bitbake -c fetchall core-image-minimal

# Build the image (you can change the target image as needed)
echo "Starting the build process..."
bitbake core-image-minimal

# Notify user of completion and next steps
echo "Build completed. The image is located in tmp/deploy/images/raspberrypi3-64/"
echo "Use the following command to flash the image to your SD card:"
echo "sudo dd if=tmp/deploy/images/raspberrypi3-64/core-image-minimal-raspberrypi3-64.rpi-sdimg of=/dev/sdX bs=4M status=progress"

#wget https://github.com/balena-io/etcher/releases/download/v2.1.0/balena-etcher_2.1.0_amd64.deb
