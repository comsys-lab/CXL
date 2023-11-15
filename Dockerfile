#################### Reference ####################
# cloudsuite/data-caching:server @dockerhub
# (URL) https://hub.docker.com/layers/cloudsuite/data-caching/server/images/sha256-84cb4ba1a28a7f16b118dbf09d0b5d0705fac0d9dc44bbb95719642ff4844ef1?context=explore
###################################################

FROM cloudsuite/base-os:ubuntu

RUN groupadd -r memcache && useradd -r -g memcache memcache

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends libevent-2.1-7 && rm -rf /var/lib/apt/lists/*

RUN buildDeps='curl gcc libc6-dev libevent-dev make perl' \
		&& set -x \
		&& apt-get update && apt-get install -y $buildDeps --no-install-recommends \
		&& rm -rf /var/lib/apt/lists/* \
		# Install modified memcached
		&& mkdir -p /usr/src/memcached && cd /usr/src \
		&& apt update && apt-get install -y git && git clone --recursive https://github.com/comsys-lab/CXL.git \
		&& cd /usr/src/CXL && tar -xzf memcached_hmsdk.tar.gz -C /usr/src/memcached --strip-components=1 && rm /usr/src/CXL/memcached_hmsdk.tar.gz \
		# Install hmsdk
		# Prerequisite: kernel for hmsdk has been built.
		&& cd /usr/src && git clone --recursive https://github.com/SKhynix/hmsdk.git \
		# Option 1: Build cemalloc package
		&& apt-get update && apt-get install -y cmake && apt-get install -y autoconf \
		#&& apt-get update && apt-get install -y build-essential zlib1g-dev libncurses5-dev libgdbm-dev libnss3-dev libssl-dev libsqlite3-dev libreadline-dev libffi-dev curl libbz2-dev \
		#&& curl -O https://www.python.org/ftp/python/3.11.0/Python-3.11.0.tar.xz && tar -xf Python-3.11.0.tar.xz \
		#&& rm Python-3.11.0.tar.xz && cd Python-3.11.0
		#&& ./configure --enable-optimizations && make -j $(nproc) && make altinstall
		#&& cd .. && cd hmsdk/cemalloc/ && ./build.py \
		# Option 2: Use pre-built cemalloc package
		&& cp -r /usr/src/CXL/cemalloc_package /usr/src/hmsdk/cemalloc/ \
		# Build numactl
		&& apt-get install -y libtool \
		&& cd /usr/src/hmsdk/numactl && ./autogen.sh && ./configure && make && make install \
		# HMSDK ImplicitAPI
		&& export CE_MODE=CE_IMPLICIT && export CE_CXL_NODE=0 && export CE_ALLOC=CE_ALLOC_CXL \
		&& export LD_PRELOAD=/usr/src/hmsdk/cemalloc/cemalloc_package/libcemalloc.so \
		# Build memcached
		&& apt-get update && apt-get install -y perl && apt-get install -y m4 \
		&& apt remove -y automake && apt autoclean && apt -y autoremove \
		&& cd /usr/src && curl -SL "http://ftp.gnu.org/gnu/automake/automake-1.16.4.tar.gz" -o automake.tar.gz && tar xvfz automake.tar.gz && rm automake.tar.gz \
		&& cd automake-1.16.4 && ./configure --prefix=/usr && make && make install \
		&& cd /usr/src/memcached && ./configure && make -j$(nproc) \
		&& make install \
		&& rm -rf /usr/src/memcached \
		&& apt-get purge -y --auto-remove $buildDeps

ENTRYPOINT [ "memcached" ]

USER memcache

EXPOSE map[11211/tcp:{}]

CMD ["-t" "2" "-m" "2048" "-n" "550"]