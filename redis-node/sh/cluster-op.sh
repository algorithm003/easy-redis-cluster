
#------------------INIT PARAMETERS-----------------

interval=5

ips_key=${REDIS_NODE_KEY_NAMESPACE}:ips

curr_pod_index=`echo ${POD_NAME} | awk -F '-' '{print $3}'`
pod_name_prefix=`echo ${POD_NAME} | awk -F '-' '{print $1"-"$2"-"}'`

pod_host=${pod_host-${POD_IP}}  # when the index 0 pod, only can use its ip to fix slots, then share its ip by its instance

#--------------------BASE CONTROL------------------

if [ ${REDIS_NODE_MIN_POD_REPLICAS} -lt ${REDIS_CLUSTER_MIN_POD_REPLICAS} ]; then

	echo "at least ${REDIS_CLUSTER_MIN_POD_REPLICAS} PODS" >> ${REDIS_NODE_SH_LOG_FILENAME};
	res=`redis-cli shutdown nosave`;

fi

#-----------------GET A AVAIABLE HOST--------------

pod_index=0  # start from index 1 pod
while [ $pod_index -lt $curr_pod_index ]; do  # why loop? getting a avaiable host that other pod will get pod ip from redis
	pod_host=$pod_name_prefix$pod_index.${REDIS_NODE_POD_HOST_END_PART};
	echo ping >> ${REDIS_NODE_SH_LOG_FILENAME};
	res=`redis-cli -c -h $pod_host -p ${REDIS_NODE_CLIENT_PORT} ping`;
	if [ $? -eq 0 ]; then break; fi
	pod_index=`expr ${pod_index} + 1`
	sleep 2;
done

#---------------------COMMANDS---------------------

# save lastest ips, when pod restart, its ip maybe change
ltrim="-c -h $pod_host -p ${REDIS_NODE_CLIENT_PORT} ltrim $ips_key 0 ${REDIS_NODE_MIN_POD_REPLICAS}"
# append by left side, use 0 index to visit, can visit different pod, and keep latest
lpush="-c -h $pod_host -p ${REDIS_NODE_CLIENT_PORT} lpush $ips_key ${POD_IP}"

llen="-c -h $pod_host -p ${REDIS_NODE_CLIENT_PORT} llen $ips_key"
meet="-c -h $pod_host -p ${REDIS_NODE_CLIENT_PORT} cluster meet ${POD_IP} ${REDIS_NODE_CLIENT_PORT}"

rebalance="-c --cluster rebalance $POD_IP:${REDIS_NODE_CLIENT_PORT} --cluster-pipeline ${REDIS_NODE_KEY_COUNT} --cluster-use-empty-masters --cluster-replace --cluster-yes"
fix="-c --cluster fix ${POD_IP}:${REDIS_NODE_CLIENT_PORT} --cluster-yes"

check="-c -h $pod_host -p ${REDIS_NODE_CLIENT_PORT} --cluster check ${POD_IP}:${REDIS_NODE_CLIENT_PORT}"

#-----------------FUNCTIONS--------------

add_node_as_slave(){

	#=== BY GETTING A AVAIABLE POD IP TO ADD NODE ===
	list_len=`redis-cli $llen)`
	list_index=0
	while [ $list_index -le $list_len ]; do
		target_ip=`redis-cli -c -h $pod_host -p ${REDIS_NODE_CLIENT_PORT} lindex $ips_key $list_index`;
		echo add-node >> ${REDIS_NODE_SH_LOG_FILENAME};
		res=`redis-cli -c --cluster add-node ${POD_IP}:${REDIS_NODE_CLIENT_PORT} $target_ip:${REDIS_NODE_CLIENT_PORT} --cluster-slave`;
		if [ $? -eq 0 ]; then break; fi
		list_index=`expr ${list_index} + 1`
	done
}

do_meet(){

	echo meet >> ${REDIS_NODE_SH_LOG_FILENAME};
	res=`redis-cli $meet` || { exit 1; };

}

do_fix(){

	sleep $interval
	echo fix >> ${REDIS_NODE_SH_LOG_FILENAME};
	res=`redis-cli $fix` || { exit 1; };

}

do_rebalance(){

	sleep $interval  # why need interval time, redis cluster use gossip protocol, give sometimes to communicate with each other
	echo rebalance >> ${REDIS_NODE_SH_LOG_FILENAME};
	res=`redis-cli $rebalance` || { exit 1; };

}

add_pod_ip_to_redis(){

	echo ltrim-lpush >> ${REDIS_NODE_SH_LOG_FILENAME};
	res=`redis-cli $ltrim` || { exit 1; };
	res=`redis-cli $lpush` || { exit 1; };

}

check(){

	sleep $interval;
	echo check >> ${REDIS_NODE_SH_LOG_FILENAME};
	res=`redis-cli $check`;

}

#====================== MAIN LOGIC  =======================

# = RESTART POD LOGIC =
	# situation 1. occur error to restart
	# situation 2. normal scale, first scale down, then scale up

if [ -f ${REDIS_NODE_READINESS_FILENAME} ]; then  # when pod restart, also need to store pod ip to redis

	check;

	if [ $? -eq 0 ]; then
		add_pod_ip_to_redis;
		exit 0;
	fi

fi

sleep $interval

# = CREATE POD LOGIC =
#   - seperate 2 parts:
#     1. 6 pods
#     2. more than 6 pods

if [ $curr_pod_index -le ${REDIS_CLUSTER_MIN_POD_REPLICAS} ]; then  # part 1

	master_end_index=$((${REDIS_CLUSTER_MIN_POD_REPLICAS}/2-1))

	if [ $curr_pod_index -eq 0 ]; then
	# the first pod will use its ip to fix slots, so the following pod can store ip in it.

		do_fix;

	elif [ $curr_pod_index -le $master_end_index ]; then
	# login to other pod, then meet to myself

		do_meet;

	elif [ $curr_pod_index -gt $master_end_index ]; then

		add_node_as_slave;

	else

		 echo unknow_exception >> ${REDIS_NODE_SH_LOG_FILENAME};

	fi

	if [ $curr_pod_index -eq $master_end_index ]; then

		do_rebalance;

	fi

else  # part 2

	if [ $(($curr_pod_index%2)) -eq 0 ]; then

		# i am slave
		add_node_as_slave;

	else
		# i am master
		do_meet;
		do_fix;  # try to fix slots, sometimes some slots has a wrong position
		do_rebalance;
		do_fix;  # try to fix slots again

	fi

fi
# HOW TO WORK? min_replicas is 6
# 012345|6789 curr_pod_index
# 012   | 7 9 master
#    345|6 8  slave

# = STORE POD IP TO REDIS =

add_pod_ip_to_redis;  # the every new pod need to store its ip to redis
