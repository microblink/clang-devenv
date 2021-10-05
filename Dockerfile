FROM microblinkdev/alpine-clang:13.0.0

# install glibc in order to be able to run programs built against it (adb, emscripten, android NDK, various other tools)
ARG GLIBC_VERSION=2.34

RUN mkdir -p /home/glibc && \
    cd /home/glibc && \
    wget -q -O /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub && \
    wget https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}-r0/glibc-${GLIBC_VERSION}-r0.apk && \
    apk add glibc-${GLIBC_VERSION}-r0.apk && \
    cd /home && \
    rm -rf glibc

# install LFS and setup global .gitignore for both
# root and every other user logged with -u user:group docker run parameter
RUN apk add --no-cache openjdk11-jre-headless git git-lfs py3-pip dbus && \
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

# compile Ninja from source
ARG NINJA_VERSION=1.10.2

# build Ninja from source
RUN mkdir -p /home/ninja && \
    cd /home/ninja && \
    wget -O ninja.tar.gz https://github.com/ninja-build/ninja/archive/v${NINJA_VERSION}.tar.gz  && \
    tar xf ninja.tar.gz    && \
    mkdir build      && \
    cd build && \
    python3 ../ninja-${NINJA_VERSION}/configure.py --bootstrap && \
    mv ninja /usr/local/bin && \
    cd /home && rm -rf ninja

# create gcc/g++ symlinks in /usr/bin (compatibility with legacy clang conan profile)
# and also replace binutils tools with LLVM version
RUN ln -s /usr/local/bin/clang /usr/bin/clang && \
    ln -s /usr/local/bin/clang++ /usr/bin/clang++ && \
    ln /usr/local/bin/llvm-ar /usr/bin/ar && \
    ln /usr/local/bin/llvm-nm /usr/bin/nm && \
    ln /usr/local/bin/llvm-ranlib /usr/bin/ranlib && \
    ln /usr/local/bin/lld /usr/bin/ld

ARG CMAKE_VERSION=3.21.3

# download and install CMake
RUN cd /home && \
    wget https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz && \
    tar xf cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz && \
    cd cmake-${CMAKE_VERSION}-linux-x86_64 && \
    find . -type d -exec mkdir -p /usr/local/\{} \; && \
    find . -type f -exec mv \{} /usr/local/\{} \; && \
    cd .. && \
    rm -rf *

ARG CONAN_VERSION=1.41.0

# download and install conan and LFS and set global .gitignore
RUN python3 -m pip install conan==${CONAN_VERSION} grip

ENV LD_LIBRARY_PATH="/usr/local/lib:/usr/local/lib64"

# Install Android SDK
RUN cd /home && mkdir android-sdk && cd android-sdk && \
    wget -O sdk.zip https://dl.google.com/android/repository/commandlinetools-linux-6858069_latest.zip && \
    unzip sdk.zip && rm -f sdk.zip

RUN cd /home/android-sdk/cmdline-tools && mkdir latest && mv * latest/ || true

ENV ANDROID_SDK_ROOT="/home/android-sdk"    \
    PATH="${PATH}:/home/android-sdk/platform-tools:/home/android-sdk/cmdline-tools/latest/bin"

# install Android SDK and tools and create development folders (mount points)
# note: this is a single run statement to prevent having two large docker layers when pushing
#       (one containing the android SDK and another containing the chmod-ed SDK)
RUN cd /home/android-sdk/cmdline-tools/latest/bin/ && \
    yes | ./sdkmanager --licenses && \
    ./sdkmanager 'platforms;android-30' 'build-tools;30.0.3' 'platforms;android-29' 'build-tools;29.0.3' && \
    mkdir -p /home/source           && \
    mkdir -p /home/build            && \
    mkdir -p /home/test-data        && \
    mkdir -p /home/secure-test-data && \
    chmod -R 777 /home

# install latest chromium and other packages needed for development
RUN apk add --no-cache chromium libatomic_ops-dev make gtk+3.0-dev zip gdb libxt-dev ccache openssh binutils-gold perl gcc
