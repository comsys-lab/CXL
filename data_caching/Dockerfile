FROM cloudsuite/base-os:ubuntu

# This is based on the official memcached Dockerfile

# add our user and group first to make sure their IDs get assigned consistently, regardless of whatever dependencies get added
RUN groupadd -r memcache && useradd -r -g memcache memcache

ENV DEBIAN_FRONTEND noninteractive

ENV MEMCACHED_VERSION 1.6.15

# this checksum was not provided with the author of memcached, it is checksum of the working downloaded version
ENV MEMCACHED_SHA1 badcfa0d65f5797cc9c2f957f3fbfedbd8c13411

# Install memcached
RUN set -x && buildDeps='curl gcc libc6-dev libevent-dev make perl git ca-certificates cmake python3 build-essential libtool' \
	&& apt-get update && apt-get install -y $buildDeps --no-install-recommends && rm -rf /var/lib/apt/lists/* \
	&& curl -SL "http://memcached.org/files/memcached-$MEMCACHED_VERSION.tar.gz" -o memcached.tar.gz && echo "$MEMCACHED_SHA1 memcached.tar.gz" | sha1sum -c - \
	&& mkdir -p /usr/src/memcached && tar -xzf memcached.tar.gz -C /usr/src/memcached --strip-components=1 && rm memcached.tar.gz && cd /usr/src/memcached \
	&& ./configure && make -j $(nproc) && make install \
	&& rm -rf /usr/src/memcached \

# Install HMSDK
RUN set -x && cd /usr/src \
	&& git clone --recursive --shallow-submodules "https://github.com/SKhynix/hmsdk.git" && apt-get update && apt-get install -y autoconf \
	&& cd /usr/src/hmsdk/cemalloc/ && ./build.py \

# Build numactl
RUN set -x && cd /usr/src/hmsdk/numactl \
	&& ./autogen.sh && ./configure && make && make install \
	&& apt-get purge -y --auto-remove $buildDeps \

# HMSDK implicitAPI
RUN set -x && export CE_MODE=CE_IMPLICIT && export CE_CXL_NODE=1 && export CE_ALLOC=CE_ALLOC_CXL \
	&& export LD_PRELOAD=/usr/src/hmsdk/cemalloc/cemalloc_package/libcemalloc.so

ENTRYPOINT ["memcached"]

USER memcache

EXPOSE 11211

CMD ["-t" "2" "-m" "2048" "-n" "550"]
