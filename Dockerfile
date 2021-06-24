FROM microblinkdev/centos-ninja:1.10.2 as ninja
FROM microblinkdev/centos-ccache:3.7.11 as ccache
FROM microblinkdev/centos-git:2.30.0 as git
FROM microblinkdev/centos-python:3.8.3 as python

FROM microblinkdev/centos-clang:9.0.1

COPY --from=ninja /usr/local/bin/ninja /usr/local/bin/
COPY --from=python /usr/local /usr/local/
COPY --from=git /usr/local /usr/local/
COPY --from=ccache /usr/local /usr/local/

# install LFS and setup global .gitignore for both
# root and every other user logged with -u user:group docker run parameter
RUN yum -y install epel-release && \
    yum -y install openssh-clients glibc-static java-devel which gtk3-devel zip bzip2 make gdb libXt perl-Digest-MD5 libjpeg-devel openssl11-devel && \
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
# support for conan packages to discover OpenSSL 1.1.1
ENV CONAN_CMAKE_CUSTOM_OPENSSL_ROOT_DIR=/usr/include/openssl11      \
    CONAN_CMAKE_CUSTOM_OPENSSL_LIBRARIES=/usr/lib64/openssl11       \
    CONAN_CMAKE_CUSTOM_OPENSSL_SSL_LIBRARY=/usr/lib64/openssl11     \
    CONAN_CMAKE_CUSTOM_OPENSSL_CRYPTO_LIBRARY=/usr/lib64/openssl11  \
    CONAN_CMAKE_CUSTOM_OPENSSL_INCLUDE_DIR=/usr/include/openssl11

# create gcc/g++ symlinks in /usr/bin (compatibility with legacy clang conan profile)
# and also replace binutils tools with LLVM version
RUN ln -s /usr/local/bin/clang /usr/bin/clang && \
    ln -s /usr/local/bin/clang++ /usr/bin/clang++ && \
    rm /usr/bin/nm /usr/bin/ranlib /usr/bin/ar && \
    ln /usr/local/bin/llvm-ar /usr/bin/ar && \
    ln /usr/local/bin/llvm-nm /usr/bin/nm && \
    ln /usr/local/bin/llvm-ranlib /usr/bin/ranlib && \
    ln -s /usr/local/bin/ccache /usr/bin/ccache

ARG CMAKE_VERSION=3.19.3

# download and install CMake
RUN cd /home && \
    curl -o cmake.tar.gz -L https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-Linux-x86_64.tar.gz && \
    tar xf cmake.tar.gz && \
    cd cmake-${CMAKE_VERSION}-Linux-x86_64 && \
    find . -type d -exec mkdir -p /usr/local/\{} \; && \
    find . -type f -exec mv \{} /usr/local/\{} \; && \
    cd .. && \
    rm -rf *

ARG CONAN_VERSION=1.37.2

# download and install conan and LFS and set global .gitignore
RUN python3 -m pip install conan==${CONAN_VERSION} grip

ENV LD_LIBRARY_PATH="/usr/local/lib:/usr/local/lib64"

# Install jsawk
RUN cd /tmp/ && \
    curl -L http://github.com/micha/jsawk/raw/master/jsawk > jsawk && \
    chmod 755 jsawk && mv jsawk /usr/bin/ && \
    yum install -y js
# Install restry
RUN yum -y install perl-JSON && \
    curl -L https://raw.githubusercontent.com/micha/resty/master/pp > /usr/bin/pp && \
    chmod +x /usr/bin/pp && \
    sed -i '1 s/^.*$/#!\/usr\/bin\/perl -0007/' /usr/bin/pp

# Install Android SDK
RUN yum -y install unzip && \
    cd /home && mkdir android-sdk && cd android-sdk && \
    curl -L -o sdk.zip https://dl.google.com/android/repository/commandlinetools-linux-6858069_latest.zip && \
    unzip sdk.zip && rm -f sdk.zip

RUN cd /home/android-sdk/cmdline-tools && mkdir latest && mv * latest/ || true

ENV ANDROID_SDK_ROOT="/home/android-sdk"    \
    PATH="${PATH}:/home/android-sdk/platform-tools"

# install Android SDK and tools and create development folders (mount points)
# note: this is a single run statement to prevent having two large docker layers when pushing
#       (one containing the android SDK and another containing the chmod-ed SDK)
RUN cd /home/android-sdk/cmdline-tools/latest/bin/ && \
    yes | ./sdkmanager --licenses && \
    ./sdkmanager 'platforms;android-30' 'build-tools;30.0.2' 'platforms;android-29' 'build-tools;29.0.2' && \
    mkdir -p /home/source           && \
    mkdir -p /home/build            && \
    mkdir -p /home/test-data        && \
    mkdir -p /home/secure-test-data && \
    chmod --recursive 777 /home
