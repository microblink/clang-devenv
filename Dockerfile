FROM microblinkdev/microblink-ninja:1.11.1 as ninja
FROM microblinkdev/microblink-git:2.43.0 as git

##------------------------------------------------------------------------------
# NOTE: don't forget to also update `latest` tag
#       regctl image copy microblinkdev/clang-devenv:14.0.2 microblinkdev/clang-devenv:latest
##------------------------------------------------------------------------------
FROM microblinkdev/microblink-clang:17.0.6

COPY --from=ninja /usr/local/bin/ninja /usr/local/bin/
COPY --from=git /usr/local /usr/local/

# install LFS and setup global .gitignore for both
# root and every other user logged with -u user:group docker run parameter
RUN apt install -y libgtk-3-0 zip bzip2 make libssl-dev gzip unzip file pkg-config && \
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

ARG CMAKE_VERSION=3.28.2
ARG BUILDPLATFORM

# download and install CMake
RUN cd /home && \
    if [ "$BUILDPLATFORM" == "linux/arm64" ]; then arch=aarch64; else arch=x86_64; fi && \
    curl -o cmake.tar.gz -L https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-${arch}.tar.gz && \
    tar xf cmake.tar.gz && \
    cd cmake-${CMAKE_VERSION}-linux-${arch} && \
    find . -type d -exec mkdir -p /usr/local/\{} \; && \
    find . -type f -exec mv \{} /usr/local/\{} \; && \
    cd .. && \
    rm -rf *

ARG CONAN_VERSION=2.0.17

# download and install conan, grip and virtualenv (pythong packages needed for build)
RUN python3 -m pip install conan==${CONAN_VERSION} grip virtualenv

# install maven for purposes of building core-recognizer-runner artifacts
RUN apt install -y maven

############################################
# everything below this line is Intel-only #
############################################

ARG WABT_VERSION=1.0.33

# download and install WASM binary tools, used for wasm validation
RUN if [ "$BUILDPLATFORM" == "linux/amd64" ]; then \
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
RUN if [ "$BUILDPLATFORM" == "linux/amd64" ]; then \
        apt install -y openjdk-17-jdk && \
        cd /home && mkdir android-sdk && cd android-sdk && \
        curl -L -o sdk.zip https://dl.google.com/android/repository/commandlinetools-linux-6858069_latest.zip && \
        unzip sdk.zip && rm -f sdk.zip && \
        cd /home/android-sdk/cmdline-tools && mkdir latest && mv * latest/ || true; \
    fi

ENV ANDROID_SDK_ROOT="/home/android-sdk"    \
    PATH="${PATH}:/home/android-sdk/platform-tools:/home/android-sdk/cmdline-tools/latest/bin"

ARG UBER_ADB_TOOLS_VERSION=1.0.4

# install Android SDK and tools and create development folders (mount points)
# note: this is a single run statement to prevent having two large docker layers when pushing
#       (one containing the android SDK and another containing the chmod-ed SDK)
RUN if [ "$BUILDPLATFORM" == "linux/amd64" ]; then \
        cd /home/android-sdk/cmdline-tools/latest/bin/ && \
        yes | ./sdkmanager --licenses && \
        ./sdkmanager 'platform-tools' 'platforms;android-33' 'build-tools;33.0.2' 'platforms;android-32' 'build-tools;32.0.0' && \
        mkdir -p /home/source           && \
        mkdir -p /home/build            && \
        mkdir -p /home/test-data        && \
        mkdir -p /home/secure-test-data && \
        chmod --recursive 777 /home     && \
        cd /home/android-sdk/           && \
        curl -L -o uber-adb-tools.jar https://github.com/patrickfav/uber-adb-tools/releases/download/v${UBER_ADB_TOOLS_VERSION}/uber-adb-tools-${UBER_ADB_TOOLS_VERSION}.jar;  \
    fi

# download and install latest chrome and node/npm, needed for emscripten tests
RUN if [ "$BUILDPLATFORM" == "linux/amd64" ]; then \
        cd /home && \
        curl -o chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
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
ENV LIBRARY_PATH="/usr/lib/gcc/aarch64-linux-gnu/11:/usr/lib/gcc/x86_64-linux-gnu/11"

