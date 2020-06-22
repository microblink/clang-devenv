FROM microblinkdev/centos-ninja:1.10.0 as ninja
FROM microblinkdev/centos-ccache:3.7.10 as ccache
FROM microblinkdev/centos-git:2.27.0 as git
FROM microblinkdev/centos-python:3.8.0 as python
FROM microblinkdev/centos-gcc:9.2.0 as libstdcpp_provider

FROM microblinkdev/centos-clang:9.0.1

COPY --from=ninja /usr/local/bin/ninja /usr/local/bin/
COPY --from=python /usr/local /usr/local/
COPY --from=git /usr/local /usr/local/
COPY --from=ccache /usr/local /usr/local/

# install LFS and setup global .gitignore for both
# root and every other user logged with -u user:group docker run parameter
RUN yum -y install openssh-clients glibc-static java-devel which gtk3-devel zip bzip2 make libXt perl-Digest-MD5 && \
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

# ARG FIREFOX_VERSION=70.0

# # download and install Firefox
# RUN cd /usr/local && \
#     curl -o firefox.tar.bz2 http://ftp.mozilla.org/pub/firefox/releases/${FIREFOX_VERSION}/linux-x86_64/en-US/firefox-${FIREFOX_VERSION}.tar.bz2 && \
#     tar xf firefox.tar.bz2 && \
#     rm firefox.tar.bz2 && \
#     ln -s /usr/local/firefox/firefox /usr/local/bin/firefox

ARG CMAKE_VERSION=3.17.3

# download and install CMake
RUN cd /home && \
    curl -o cmake.tar.gz -L https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-Linux-x86_64.tar.gz && \
    tar xf cmake.tar.gz && \
    cd cmake-${CMAKE_VERSION}-Linux-x86_64 && \
    find . -type d -exec mkdir -p /usr/local/\{} \; && \
    find . -type f -exec mv \{} /usr/local/\{} \; && \
    cd .. && \
    rm -rf *

ARG CONAN_VERSION=1.25.2

# download and install conan and LFS and set global .gitignore
RUN python3 -m pip install conan==${CONAN_VERSION} grip

# download and install chrome
RUN cd /home && \
    curl -o chrome.rpm https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm && \
    yum -y install chrome.rpm && \
    rm chrome.rpm

# install libstdc++.so of modern GCC (required by some binaries, such as emscripten)

COPY --from=libstdcpp_provider /usr/local/lib64/libstdc++.so* /usr/local/lib64/

ENV LD_LIBRARY_PATH="/usr/local/lib:/usr/local/lib64"

# create development folders (mount points)
RUN mkdir -p /home/source           && \
    mkdir -p /home/build            && \
    mkdir -p /home/test-data        && \
    mkdir -p /home/secure-test-data && \
    chmod --recursive 777 /home

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
