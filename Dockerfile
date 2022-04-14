FROM microblinkdev/amazonlinux-ninja:1.10.2 as ninja
FROM microblinkdev/amazonlinux-ccache:4.5.1 as ccache
FROM microblinkdev/amazonlinux-git:2.35.1 as git

# Amazon Linux 2 uses python3.7 by default and LLDB is built against it
# FROM microblinkdev/centos-python:3.8.3 as python

FROM microblinkdev/amazonlinux-clang:14.0.1

COPY --from=ninja /usr/local/bin/ninja /usr/local/bin/
# COPY --from=python /usr/local /usr/local/
COPY --from=git /usr/local /usr/local/
COPY --from=ccache /usr/local /usr/local/

# install LFS and setup global .gitignore for both
# root and every other user logged with -u user:group docker run parameter
RUN yum -y install openssh-clients which gtk3-devel zip bzip2 make gdb libXt perl-Digest-MD5 openssl11-devel tar gzip zip unzip xz python3-devel procps && \
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

# create gcc/g++ symlinks in /usr/bin (compatibility with legacy clang conan profile)
# and also replace binutils tools with LLVM version
RUN ln -s /usr/local/bin/clang /usr/bin/clang && \
    ln -s /usr/local/bin/clang++ /usr/bin/clang++ && \
    rm /usr/bin/nm /usr/bin/ranlib /usr/bin/ar && \
    ln -s /usr/local/bin/llvm-ar /usr/bin/ar && \
    ln -s /usr/local/bin/llvm-nm /usr/bin/nm && \
    ln -s /usr/local/bin/llvm-ranlib /usr/bin/ranlib && \
    ln -s /usr/local/bin/ccache /usr/bin/ccache

ARG CMAKE_VERSION=3.23.1
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

ARG CONAN_VERSION=1.47.0

# download and install conan, grip and virtualenv (pythong packages needed for build)
RUN python3 -m pip install conan==${CONAN_VERSION} grip virtualenv

############################################
# everything below this line is Intel-only #
############################################

ARG WABT_VERSION=1.0.26

# download and install WASM binary tools, used for wasm validation
RUN if [ "$BUILDPLATFORM" == "linux/amd64" ]; then \
        cd /home && \
        git clone --depth 1 --shallow-submodules --branch ${WABT_VERSION} --recursive  https://github.com/WebAssembly/wabt && \
        mkdir wabt-build && \
        cd wabt-build && \
        cmake -GNinja -DCMAKE_INSTALL_RPATH=/usr/local/lib -DCMAKE_INSTALL_PREFIX=/usr/local ../wabt && \
        ninja && \
        ninja install && \
        cd .. && \
        rm -rf *; \
    fi

# Install jsawk
RUN if [ "$BUILDPLATFORM" == "linux/amd64" ]; then \
        cd /tmp/ && \
        curl -L http://github.com/micha/jsawk/raw/master/jsawk > jsawk && \
        chmod 755 jsawk && mv jsawk /usr/bin/ && \
        yum install -y js; \
    fi

# Install restry
RUN if [ "$BUILDPLATFORM" == "linux/amd64" ]; then \
        yum -y install perl-JSON && \
        curl -L https://raw.githubusercontent.com/micha/resty/master/pp > /usr/bin/pp && \
        chmod +x /usr/bin/pp && \
        sed -i '1 s/^.*$/#!\/usr\/bin\/perl -0007/' /usr/bin/pp; \
    fi

# Install Android SDK
RUN if [ "$BUILDPLATFORM" == "linux/amd64" ]; then \
        yum -y install java-11-amazon-corretto-headless && \
        cd /home && mkdir android-sdk && cd android-sdk && \
        curl -L -o sdk.zip https://dl.google.com/android/repository/commandlinetools-linux-6858069_latest.zip && \
        unzip sdk.zip && rm -f sdk.zip && \
        cd /home/android-sdk/cmdline-tools && mkdir latest && mv * latest/ || true; \
    fi

ENV ANDROID_SDK_ROOT="/home/android-sdk"    \
    PATH="${PATH}:/home/android-sdk/platform-tools:/home/android-sdk/cmdline-tools/latest/bin"

# install Android SDK and tools and create development folders (mount points)
# note: this is a single run statement to prevent having two large docker layers when pushing
#       (one containing the android SDK and another containing the chmod-ed SDK)
RUN if [ "$BUILDPLATFORM" == "linux/amd64" ]; then \
        cd /home/android-sdk/cmdline-tools/latest/bin/ && \
        yes | ./sdkmanager --licenses && \
        ./sdkmanager 'platforms;android-31' 'build-tools;31.0.0' 'platforms;android-30' 'build-tools;30.0.3' && \
        mkdir -p /home/source           && \
        mkdir -p /home/build            && \
        mkdir -p /home/test-data        && \
        mkdir -p /home/secure-test-data && \
        chmod --recursive 777 /home; \
    fi

# download and install latest chrome
RUN if [ "$BUILDPLATFORM" == "linux/amd64" ]; then \
        cd /home && \
        curl -o chrome.rpm https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm && \
        yum -y install chrome.rpm && \
        rm chrome.rpm; \
    fi
