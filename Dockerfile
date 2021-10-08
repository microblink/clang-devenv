FROM microblinkdev/centos-ninja:1.10.2 as ninja
FROM microblinkdev/centos-ccache:3.7.11 as ccache
FROM microblinkdev/centos-git:2.30.0 as git

# Amazon Linux 2 uses python3.7 by default and LLDB is built against it
# FROM microblinkdev/centos-python:3.8.3 as python

FROM microblinkdev/amazonlinux-clang:13.0.0

COPY --from=ninja /usr/local/bin/ninja /usr/local/bin/
# COPY --from=python /usr/local /usr/local/
COPY --from=git /usr/local /usr/local/
COPY --from=ccache /usr/local /usr/local/

# install LFS and setup global .gitignore for both
# root and every other user logged with -u user:group docker run parameter
RUN yum -y install openssh-clients java-11-amazon-corretto-headless which gtk3-devel zip bzip2 make gdb libXt perl-Digest-MD5 openssl11-devel && \
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
    ln /usr/local/bin/llvm-ar /usr/bin/ar && \
    ln /usr/local/bin/llvm-nm /usr/bin/nm && \
    ln /usr/local/bin/llvm-ranlib /usr/bin/ranlib && \
    ln -s /usr/local/bin/ccache /usr/bin/ccache

ARG CMAKE_VERSION=3.21.3

# download and install CMake
RUN cd /home && \
	yum -y install tar && \
    curl -o cmake.tar.gz -L https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz && \
    tar xf cmake.tar.gz && \
    cd cmake-${CMAKE_VERSION}-linux-x86_64 && \
    find . -type d -exec mkdir -p /usr/local/\{} \; && \
    find . -type f -exec mv \{} /usr/local/\{} \; && \
    cd .. && \
    rm -rf *

ARG CONAN_VERSION=1.41.0

# download and install conan, grip and virtualenv (pythong packages needed for build)
RUN python3 -m pip install conan==${CONAN_VERSION} grip virtualenv

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
    chmod --recursive 777 /home

# download and install latest chrome
RUN cd /home && \
    curl -o chrome.rpm https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm && \
    yum -y install chrome.rpm && \
    rm chrome.rpm
