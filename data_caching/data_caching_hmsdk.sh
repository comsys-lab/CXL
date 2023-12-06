#!/bin/bash
set -x
################ configurations #####################

# Node information.
#node 0 cpus: 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 
# 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95
# node 1 cpus: 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63
# 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127
# Client configuration

# Client configuration
CLIENT_CPUS=64-127 # 32-63
CLIENT_MEMORY=128g

PERF_EVENTS=instructions:u,instructions:k,cycles:u,cycles:k

# Server configurations
SERVER_MEMORY=128g
SERVER_CON=2100

# HMSDK configurations
CE_MODE=CE_IMPLICIT
CE_CXL_NODE=0
CE_ALLOC=CE_ALLOC_CXL
LD_PRELOAD=/usr/src/hmsdk/cemalloc/cemalloc_package/libcemalloc.so

# Memcached configurations; entrypoint.sh
WORKER_NUM=12 #client thread
MEMCACHED_MEMORY=10240
DATASET_SCALE=28 #30
MEASURE_TIME=180 #perf measurement time
GET_RATIO=0.8
CONNECTION=200
RPS=100000
STATISTICS_INTERVAL=1

# ouput files
OUT=out   
RESULTS=experiments
PERF_LOG=$OUT/perf.txt
CLIENT_LOG=$OUT/client-result.txt
CLIENT_SUMMARY=$OUT/summary.txt
UTIL_LOG=$OUT/util.txt

# SERVER_IMAGE=zilutian/data-caching:server-amd64 # Modified: arm64 -> amd64
# CLIENT_IMAGE=zilutian/data-caching:client-amd64 # Modified: arm64 -> amd64
SERVER_IMAGE=memcached_hmsdk:node1
CLIENT_IMAGE=cloudsuite/data-caching:client
NET=data_caching_net

SERVER_CONTAINER=dc-server
CLIENT_CONTAINER=dc-client
CWD=`pwd`


################ helper functions #####################
function clean_containers(){
    # remove all containers whose name contains the keyword 
    [ "$(docker ps -a | grep $1)" ] && echo "containers match $1 are found for removal" && docker ps --filter name="$1" -aq | xargs -r docker stop | xargs -r docker rm
}

function rm_all_containers(){
    [ "$(docker ps -aq)" ] && docker stop $(docker ps -aq) | xargs docker rm
}

function create_network(){
    [ ! "$(docker network ls | grep -w ${NET})" ] && docker network create ${NET} && echo "network $NET created"
}

function start_server(){
    clean_containers $SERVER_CONTAINER
    docker run --name $SERVER_CONTAINER --privileged -e CE_MODE=$CE_MODE -e CE_CXL_NODE=$CE_CXL_NODE -e CE_ALLOC=$CE_ALLOC -e LD_PRELOAD=$LD_PRELOAD \
    --cpuset-cpus=${SERVER_CPUS} --memory=$SERVER_MEMORY --net $NET -d $SERVER_IMAGE -t $SERVER_THREAD -m $MEMCACHED_MEMORY -n 550 -c $SERVER_CON
    echo 'dc-server, 11211' > ./docker_servers/docker_servers.txt
}

function start_client(){
    clean_containers $CLIENT_CONTAINER
    # --rm -it :removed
    docker run -dit --cpuset-cpus=${CLIENT_CPUS} \
        -v $(pwd)/files/docker-entrypoint.sh:/entrypoint.sh \
        -v $(pwd)/docker_servers:/usr/src/memcached/memcached_client/docker_servers/ \
        --memory=$CLIENT_MEMORY --entrypoint=/entrypoint.sh \
        --name $CLIENT_CONTAINER --net $NET $CLIENT_IMAGE
    
    # DEBUG
    docker ps
}

function run(){
    # scale and warmup
    docker exec -it $CLIENT_CONTAINER /bin/bash /entrypoint.sh --m="S&W" --S=$DATASET_SCALE --D=$MEMCACHED_MEMORY --w=$WORKER_NUM --T=$STATISTICS_INTERVAL
    
    # Just warmup if the scaled file already exists
    #docker exec -it $CLIENT_CONTAINER /bin/bash /entrypoint.sh --m="W" --S=$DATASET_SCALE --D=$MEMCACHED_MEMORY --w=$WORKER_NUM --T=$STATISTICS_INTERVAL

    # Run the benchmark
    # TODO: Redirect a result to the $OUT file.
    docker exec -it $CLIENT_CONTAINER timeout $MEASURE_TIME /bin/bash /entrypoint.sh --m="RPS" --S=$DATASET_SCALE --g=$GET_RATIO --c=$CONNECTION --w=$WORKER_NUM --T=$STATISTICS_INTERVAL --r=$RPS > $CLIENT_LOG

    latency_summary
    rps_summary
    log_client # Function is missing
}

function latency_summary(){
    echo "median 95th latency" >> $CLIENT_SUMMARY
    TOT=$(cat $CLIENT_LOG | grep -A1 95th | grep -v 95th | awk '{print $10}'| sed '/^$/d' | wc -l)
    cat $CLIENT_LOG | grep -A1 95th | grep -v 95th | awk '{print $10}'| sed '/^$/d' | sort | sed -n "$((TOT/2))p" >> $CLIENT_SUMMARY
}

function rps_summary(){
    echo "median achieved rps" >> $CLIENT_SUMMARY
    TOT=$(cat $CLIENT_LOG | grep -A1 95th | grep -v 95th | awk '{print $10}'| sed '/^$/d' | wc -l)
    cat $CLIENT_LOG | grep -A1 95th | grep -v 95th | awk '{print $2}'| sed '/^$/d' | sort | sed -n "$((TOT/2))p" >> $CLIENT_SUMMARY
    #echo "min achieved rps" >> $CLIENT_SUMMARY
    #cat out/client-result.txt | grep -A1 95th | grep -v 95th | awk '{print $2}'| sed '/^$/d' | sort | sed -n '1p' >> $CLIENT_SUMMARY
}

function log_folder () {
    if [[ ! -d $RESULTS ]]; then
        (($DEV)) && echo "create experimental folder $RESULTS"
    mkdir $RESULTS
    fi

    if [[ ! -d $OUT ]]; then
        (($DEV)) && echo "create tmp folder $OUT"
        mkdir $OUT
    else
        exp_cnt=`ls $RESULTS | grep -Eo [0-9]+ | sort -rn | head -n 1`
        (($DEV)) && echo "max exp count is $exp_cnt"
        [ "$(ls -A $OUT)" ] && mv $OUT $RESULTS/$((exp_cnt + 1)) && mkdir $OUT
    fi
}

################ execution #####################
rm_all_containers
create_network 

#for s in 1 2 4 6 8 12 14 20 24 28; do
# for s in 28 20 14 12 8 6 4 2 1; do #original
for s in 64; do
    cpu='' 
    for ((j=0;j<s;j++)) do
        cpu=$cpu$((j)),
    done
    cpu=${cpu::-1}
    SERVER_CPUS=$cpu
    SERVER_THREAD=$((s*2))


    echo 'SERVER_CPU='$cpu'
    SERVER_CPU_NO='$s'
    DATASET_SCALE='$DATASET_SCALE'
    MEMCACHED_MEMORY='$MEMCACHED_MEMORY'
    WORKER_NUM='$WORKER_NUM'
    SERVER_CON='$SERVER_CON'
    CLIENT_MEMORY='$CLIENT_MEMORY'
    SERVER_MEMORY='$SERVER_MEMORY'
    MEASURE_TIME='$MEASURE_TIME'
    CLIENT_CPUS='$CLIENT_CPUS'
    SERVER_THREAD='$SERVER_THREAD > $OUT/user.cfg

    start_server 
    start_client
    run
    log_folder
        
done

rm_all_containers