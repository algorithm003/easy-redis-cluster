
CONF=/data/${REDIS_NODE_CLUSTER_CONFIG_FILENAME}
if [ -f ${CONF} ]; then
  if [ -z "${POD_IP}" ]; then
    exit 1;
  fi
  sed -i.bak -e "/myself/ s/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/${POD_IP}/" ${CONF} || { exit 1; };
  # when pod restart, update pod ip to conf file
  echo fix-ip >> /data/${REDIS_NODE_SH_LOG_FILENAME} || { exit 1; };
fi
