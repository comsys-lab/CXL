#!/bin/bash

set -x
###################### CONFIGURATIONS #################
warm=3000000 # number of warmup request
rec=15000000  # 15GB record count in cassandra
f_name="experiments_asp" 
mem=20g # memory size

# common configurations
CLIENT_CPUS=28-55
SERVER_MEMORY=$mem
WARMUP_THREADS=64 # thread for warmup
RECORDS=$rec
WARMUP=$warm #operations for warmup 
OPERATIONCOUNT=30000000 # number of request for measurement
TIME=180 #seconds

# output files
OUT=out
RESULTS=experiments_asp
USER_CFG=$OUT/user.cfg
PERF_LOG=$OUT/perf.txt
CLIENT_LOG=$OUT/client-result.txt
UTIL_LOG=$OUT/util.txt

CLIENT_IMAGE=cloudsuite/data-serving:client
SERVER_IMAGE=cloudsuite/data-serving:server


CLIENT_CONTAINER=cassandra-client
SERVER_CONTAINER=cassandra-server

HOSTNAME=cassandra-server
NET=serving_network 


#PERF_EVENTS=r0011,cycles:u,cycles:k,r0008,r00E8,r0023,r0024,r0001
# PERF_EVENTS=r0011,cycles:u,cycles:k
#marco ops, L1i cache access, L1i cache refill, L1i TLB access,L1i TLB refill,
#PERF_EVENTS=r0008,r0014,r0001,r0026,r0002,r0021,branch-misses   
PERF_EVENTS=syscalls:sys_enter_futex,syscalls:sys_enter_mmap,kmem:kmalloc,kmem:mm_page_alloc,syscalls:sys_enter_fallocate,syscalls:sys_enter_sched_getscheduler 

################## HELPER FUNCTION ####################
# function to measure the perf events
function run(){
    # clean_containers $CLIENT_CONTAINER
    sudo perf stat -e $PERF_EVENTS --cpu $SERVER_CPUS -o $OUT/perf.txt \
        docker exec -t -e TIME=$TIME -e THREADS=$THREADS -e RECORDCOUNT=$RECORDS -e OPERATIONCOUNT=$OPERATIONCOUNT $CLIENT_CONTAINER /bin/bash loader.sh $SERVER_IP 1000 5000 > $CLIENT_LOG
}

# wait function until server is ready
function wait_for_ready () {
    while true;do
        if docker logs $SERVER_CONTAINER 2>/dev/null | grep -q "No gossip backlog; proceeding"; then
            echo "$1 is ready"
            break
        else
            echo "$1 is not ready"
            sleep 3
        fi
    done
}


function create_network(){
    [ ! "$(docker network ls | grep -w ${NET})" ] && docker network create ${NET} && echo "network $NET created"
}

function clean_containers(){
    # remove all containers whose name contains the keyword 
    [ "$(docker ps -a | grep $1)" ] && echo "containers match $1 are found for removal" && docker ps --filter name="$1" -aq | xargs -r docker stop | xargs -r docker rm
}


function log_helper_stdout () {
    # Look for the key words in stdout (1) of docker logs output 
    # $1: container_name, $2: keyword, $3: delay (default=1)
    while true; do
        if docker logs "$1" 2>/dev/null | grep -q "$2"; then
            echo "$1 is ready"
            return  
        else
            echo "$1 is not ready"
            sleep ${3-1}
        fi
    done
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

function rm_all_containers(){
    [ "$(docker ps -aq)" ] && docker stop $(docker ps -aq) | xargs docker rm
}

function start_server(){
    clean_containers $SERVER_CONTAINER
    docker run -dP --privileged \
        -v $(pwd)/ds_entrypoint.py:/scripts/docker-entrypoint.py \
        -v $(pwd)/$OUT/cassandra.yaml:/cassandra.yaml \
        --name ${SERVER_CONTAINER} --memory=$SERVER_MEMORY --cpuset-cpus=${SERVER_CPUS} --net ${NET} $SERVER_IMAGE 
    SERVER_PID=$(docker inspect -f '{{.State.Pid}}' $SERVER_CONTAINER)
    SERVER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $SERVER_CONTAINER) # 추가, 172.19.0.2
}

function start_client(){
    clean_containers $CLIENT_CONTAINER
    docker run -dit -e TIME=$TIME -e THREADS=$THREADS -e RECORDCOUNT=$RECORDS -e OPERATIONCOUNT=$OPERATIONCOUNT \
        --cpuset-cpus=${CLIENT_CPUS}\
        -v $(pwd)/warmup.sh:/warmup.sh \
        -v $(pwd)/loader.sh:/loader.sh \
        -v $(pwd)/setup_tables.txt:/setup_tables.txt \
        --net $NET --name $CLIENT_CONTAINER $CLIENT_IMAGE

    docker exec -it $CLIENT_CONTAINER /bin/bash warmup.sh $SERVER_IP 1000
}

function detect_stage (){
    case "$1" in
    server-ready)
        KEYWORDS="Created default superuser role"
        log_helper_stdout ${SERVER_CONTAINER} "${KEYWORDS}" 5
        ;;
    usertable-ready) 
        KEYWORDS="Keyspace usertable was created"
        log_helper_stdout ${CLIENT_CONTAINER} "${KEYWORDS}" 5
        ;;
    *) 
        printf "Unrecognized option for stage $1:\n \
            server-ready, usertable-ready"
        exit 1 
    esac
}

function copy_config(){
    set -e
    ls
    # mkdir $OUT
    [ -d "$OUT" ] && rm -rf "$OUT"; mkdir "$OUT" # Added line by sangun
    cp cassandra.yaml $OUT/cassandra.yaml # TODO: What is "cassandra.yaml" and how/where can we get this file?
    # https://github.com/apache/cassandra/blob/trunk/conf/cassandra.yaml
    sed -i 's/concurrent_writes: 32/concurrent_writes: '$1'/g' $OUT/cassandra.yaml
    set +e
}

#################### START OF EXECUTION ###############
rm_all_containers
create_network


rm -rf $RESULTS/*

# for cores in 1; do
# for cores in 28 14 12 8 6 4 2 1; do
for cores in 28; do
    # number of server core
    s=$cores
    # create the cpu ids
    cpu='' 
    for ((j=0;j<s;j++))do
        cpu=$cpu$((j)),
    done
    cpu=${cpu::-1}

    SERVER_CPUS=$cpu
    CONCURRENT_WRITES=$((cores*8))
    user_cfg='SERVER_CPUS='$cpu'\n'
    user_cfg=$user_cfg'cores ='$cores'\n'
    user_cfg=$user_cfg'CONCURRENT_WRITES ='$CONCURRENT_WRITES'\n'

    copy_config $CONCURRENT_WRITES
    start_server
    wait_for_ready

    start_client

    THREADS=16
    for ((i=0;i<3;i++)); do
        run
        user_cfg_t=$user_cfg'CLIENT_THREAD ='$THREADS'\n'
        echo -e $user_cfg_t > $USER_CFG
        log_folder
        THREADS=$((THREADS + 16))
    done
    # mv experiments $f_name'_'$s
done
# mkdir $f_name
# mv $f_name'_'* $f_name'_record'
