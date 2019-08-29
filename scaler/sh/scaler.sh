
max_slots=16384
key=${REDIS_NODE_KEY_NAMESPACE}:${REDIS_NODE_SCALE_DOWN_KEY}

a_master_host=${REDIS_NODE_NAME}-$(($RANDOM%($REDIS_NODE_MIN_POD_REPLICAS/2))).$REDIS_NODE_POD_HOST_END_PART
port=${REDIS_NODE_CLIENT_PORT}

while true; do

	data=`redis-cli -c -h ${a_master_host} -p ${port} get ${key}`;
	sleep 3;

	if [ -n "${data}" ]; then

		index=`echo ${data} | awk -F '-' '{print $1}'`
		status_=`echo ${data} | awk -F '-' '{print $2}'`

		if [[ ${status_} -ne ${REDIS_NODE_SCALE_DOWN_STATUS__FINISHED} && ${index} -ge ${REDIS_NODE_MIN_POD_REPLICAS} ]]; then

			res=`redis-cli -c -h ${a_master_host} -p ${port} set ${key} "${index}-${REDIS_NODE_SCALE_DOWN_STATUS__SCALING}" xx`;
			sleep 1;

			curr_scaling_host=${REDIS_NODE_NAME}-${index}.$REDIS_NODE_POD_HOST_END_PART

			curr_node_role=`redis-cli -c -h ${curr_scaling_host} -p ${port} role | head -n +1`;
			sleep 1;
			curr_node_id=`redis-cli -c -h ${curr_scaling_host} -p ${port} cluster myid | head -n +1`;

			if [[ ${curr_node_role} = "master" || ${curr_node_role} = "slave" ]]; then

				if [ ${curr_node_role} = "master" ]; then

					sleep 1;
					a_master_node_id=`redis-cli -c -h ${a_master_host} -p ${port} cluster myid | head -n +1`;
					sleep 1;
					res=`redis-cli -c -h ${a_master_host} -p ${port} --cluster reshard ${a_master_host}:${port} --cluster-from ${curr_node_id} --cluster-to ${a_master_node_id} --cluster-slots ${max_slots} --cluster-yes`;
					sleep 5;
					res=`redis-cli -c -h ${a_master_host} -p ${port} --cluster rebalance ${a_master_host}:${port} --cluster-replace --cluster-yes --cluster-pipeline ${REDIS_NODE_KEY_COUNT}`;
					sleep 5;

				fi

				res=`redis-cli -c -h ${a_master_host} -p ${port} --cluster del-node ${a_master_host}:${port} ${curr_node_id}`;
				sleep 1;

				res=`redis-cli -c -h ${curr_scaling_host} -p ${port} role`;

			fi

			if [[ $? -ne 0 || -z "${curr_node_id}" || -z "${curr_node_role}" ]]; then
				sleep 1;
				res=${index}-${REDIS_NODE_SCALE_DOWN_STATUS__FINISHED}
				res=`redis-cli -c -h ${a_master_host} -p ${port} set ${key} ${res} xx`;
				echo ${res} >> log
				sleep 1;
			fi
		fi
	fi
done
