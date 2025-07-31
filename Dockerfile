ARG BUILDPLATFORM

FROM --platform=$BUILDPLATFORM docker.io/microblinkdev/microblink-ninja:1.13.1 AS ninja
FROM docker.io/microblinkdev/microblink-git:2.50.1 AS git

##------------------------------------------------------------------------------
# NOTE: don't forget to also update `latest` tag
#       regctl image copy microblinkdev/clang-devenv:14.0.2 microblinkdev/clang-devenv:latest
##------------------------------------------------------------------------------
FROM docker.io/microblinkdev/microblink-clang:20.1.8

ARG BUILDPLATFORM
ARG TARGETPLATFORM

# Assert that TARGETPLATFORM is the same as BUILDPLATFORM
RUN if [ "$TARGETPLATFORM" != "$BUILDPLATFORM" ]; then echo "TARGETPLATFORM is not the same as BUILDPLATFORM"; exit 1; fi

COPY --from=ninja /usr/local/bin/ninja /usr/local/bin/
COPY --from=git /usr/local /usr/local/

# install LFS and setup global .gitignore for both
# root and every other user logged with -u user:group docker run parameter
RUN apt update && \
    apt install -y libgtk-3-dev zip bzip2 make libssl-dev gzip unzip file pkg-config && \
    git lfs install && \
    echo "~*" >> /.gitignore_global && \
    echo ".DS_Store" >> /.gitignore_global && \
    echo "[core]" >> /root/.gitconfig && \
    echo "	excludesfile = /.gitignore_global" >> /root/.gitconfig && \
    cp /root/.gitconfig /.config && \
    git config --global user.email "developer@microblink.com" && \
    git config --global user.name "Developer" && \
    dbus-uuidgen > /etc/machine-id && \
    echo "bind '\"\\e[A\": history-search-backward'" >> ~/.bashrc && \
    echo "bind '\"\\e[B\": history-search-forward'" >> ~/.bashrc && \
    echo "bind \"set completion-ignore-case on\"" >> ~/.bashrc

ENV NINJA_STATUS="[%f/%t %c/sec] "

# create gcc/g++ symlinks in /usr/bin (compatibility with clang conan profile)
# and also replace binutils tools with LLVM version
RUN ln -f -s /usr/local/bin/clang /usr/bin/clang && \
    ln -f -s /usr/local/bin/clang++ /usr/bin/clang++ && \
    ln -f -s /usr/local/bin/llvm-ar /usr/bin/ar && \
    ln -f -s /usr/local/bin/llvm-nm /usr/bin/nm && \
    ln -f -s /usr/local/bin/llvm-ranlib /usr/bin/ranlib

ARG CMAKE_VERSION=4.0.3

# download and install CMake
RUN cd /home && \
    if [ "$TARGETPLATFORM" == "linux/arm64" ]; then arch=aarch64; else arch=x86_64; fi && \
    curl -o cmake.tar.gz -L https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-${arch}.tar.gz && \
    tar xf cmake.tar.gz && \
    cd cmake-${CMAKE_VERSION}-linux-${arch} && \
    find . -type d -exec mkdir -p /usr/local/\{} \; && \
    find . -type f -exec mv \{} /usr/local/\{} \; && \
    cd .. && \
    rm -rf *

# download and install bazelisk
ARG BAZELISK_VERSION=1.26.0

RUN cd /home && \
    if [ "$TARGETPLATFORM" == "linux/arm64" ]; then arch=arm64; else arch=amd64; fi && \
    curl -o /usr/local/bin/bazel -L https://github.com/bazelbuild/bazelisk/releases/download/v${BAZELISK_VERSION}/bazelisk-linux-${arch} && \
    chmod +x /usr/local/bin/bazel

# install maven for purposes of building core-recognizer-runner artifacts
# and pipx for supporting local installations of python packages
RUN apt update && apt install -y maven pipx

ARG CONAN_VERSION=2.17.1

# download and install conan and grip
RUN pipx install conan==${CONAN_VERSION} grip uv

# allow use of conan, uv and grip installed in previous step by all users
RUN chmod go+rx /root

# prepare mount points
RUN mkdir -p /home/source           && \
    mkdir -p /home/build            && \
    mkdir -p /home/test-data        && \
    mkdir -p /home/secure-test-data

ENV PATH="/root/.local/bin:${PATH}"


############################################
# everything below this line is Intel-only #
############################################

ARG WABT_VERSION=1.0.36

# download and install WASM binary tools, used for wasm validation
RUN if [ "$TARGETPLATFORM" == "linux/amd64" ]; then \
        cd /home && \
        git clone --depth 1 --shallow-submodules --branch ${WABT_VERSION} --recursive  https://github.com/WebAssembly/wabt && \
        mkdir wabt-build && \
        cd wabt-build && \
        cmake -GNinja -DCMAKE_INSTALL_RPATH="/usr/local/lib/x86_64-unknown-linux-gnu;/usr/local/lib" -DCMAKE_INSTALL_PREFIX=/usr/local ../wabt && \
        ninja && \
        ninja install && \
        cd .. && \
        rm -rf *; \
    fi

# Install Android SDK
RUN if [ "$TARGETPLATFORM" == "linux/amd64" ]; then \
        apt install -y openjdk-17-jdk && \
        update-java-alternatives --set java-1.17.0-openjdk-amd64 && \
        cd /home && mkdir android-sdk && cd android-sdk && \
        curl -L -o sdk.zip https://dl.google.com/android/repository/commandlinetools-linux-6858069_latest.zip && \
        unzip sdk.zip && rm -f sdk.zip && \
        cd /home/android-sdk/cmdline-tools && mkdir latest && mv * latest/ || true; \
    fi

ENV ANDROID_SDK_ROOT="/home/android-sdk"    \
    ANDROID_HOME="/home/android-sdk"    \
    PATH="${PATH}:/home/android-sdk/platform-tools:/home/android-sdk/cmdline-tools/latest/bin"

ARG UBER_ADB_TOOLS_VERSION=1.0.4

# install Android SDK and tools and create development folders (mount points)
# note: this is a single run statement to prevent having two large docker layers when pushing
#       (one containing the android SDK and another containing the chmod-ed SDK)
# Note2: use platform-tools v34.0.1 due to a bug with the latest v35: https://issuetracker.google.com/issues/327026299
# Note3: use platforms;android-31 because android exe runner requires target SDK 31 in order to be able to access filesystem
#        for testing purposes
RUN if [ "$TARGETPLATFORM" == "linux/amd64" ]; then \
        cd /home/android-sdk/cmdline-tools/latest/bin/ && \
        yes | ./sdkmanager --licenses && \
        ./sdkmanager 'cmake;3.22.1' 'build-tools;35.0.0' 'platforms;android-35' 'build-tools;33.0.3' 'platforms;android-31' && \
        cd /home/android-sdk && curl -L -o platform-tools.zip https://dl.google.com/android/repository/platform-tools_r34.0.1-linux.zip && unzip -o platform-tools.zip && rm platform-tools.zip && \
        chmod --recursive 777 /home     && \
        cd /home/android-sdk/           && \
        curl -L -o uber-adb-tools.jar https://github.com/patrickfav/uber-adb-tools/releases/download/v${UBER_ADB_TOOLS_VERSION}/uber-adb-tools-${UBER_ADB_TOOLS_VERSION}.jar;  \
    fi

# Chrome version list can be found here: https://www.ubuntuupdates.org/package/google_chrome/stable/main/base/google-chrome-stable?id=202706&page=3
# Can also be "current" to use the latest version
ARG CHROME_VERSION=136.0.7103.113-1

# download and install latest chrome and node/npm, needed for emscripten tests
RUN if [ "$TARGETPLATFORM" == "linux/amd64" ]; then \
        cd /home && \
        curl -o chrome.deb -L https://dl.google.com/linux/chrome/deb/pool/main/g/google-chrome-stable/google-chrome-stable_${CHROME_VERSION}_amd64.deb && \
        apt update && \
        apt install -y ./chrome.deb ca-certificates gnupg --fix-broken && \
        rm chrome.deb && \
        mkdir -p /etc/apt/keyrings && \
        curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
        echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list && \
        apt update && \
        apt install -y nodejs; \
    fi

RUN apt autoremove && apt clean

# Set location of GCC libs
ENV LIBRARY_PATH="/usr/lib/gcc/aarch64-linux-gnu/13:/usr/lib/gcc/x86_64-linux-gnu/13"
