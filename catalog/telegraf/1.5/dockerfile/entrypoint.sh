#!/bin/bash
set -e

# check required parameters
# MONITOR_SERVICE_NAME is the stateful service to monitor.
# SERVICE_NAME is the telegraf service that monitors the stateful service.
if [ -z "$REGION" -o -z "$CLUSTER" -o -z "$SERVICE_NAME" -o -z "$MONITOR_SERVICE_NAME" -o -z "$MONITOR_SERVICE_TYPE" -o -z "$MONITOR_SERVICE_MEMBERS" ]; then
  echo "error: please specify the REGION $REGION, CLUSTER $CLUSTER, SERVICE_NAME $SERVICE_NAME, MONITOR_SERVICE_NAME $MONITOR_SERVICE_NAME, MONITOR_SERVICE_TYPE $MONITOR_SERVICE_TYPE, MONITOR_SERVICE_MEMBERS $MONITOR_SERVICE_MEMBERS"
  exit 1
fi

# telegraf config file directory
configDir="/firecamp"
if [ -n "$TEST_CONFIG_DIR" ]; then
  configDir=$TEST_CONFIG_DIR
fi

# set telegraf configs
export TEL_HOSTNAME=$SERVICE_NAME
export INTERVAL="60s"
if [ -n "$COLLECT_INTERVAL" ]; then
  export INTERVAL=$COLLECT_INTERVAL
fi

# the default servers string to replace for the input conf
FIRECAMP_SERVICE_SERVERS="firecamp-service-servers"

# get service members array
OIFS=$IFS
IFS=','
read -a members <<< "${MONITOR_SERVICE_MEMBERS}"
IFS=$OIFS


# add redis input plugin
if [ "$MONITOR_SERVICE_TYPE" = "redis" ]; then
  # check the service required parameters
  # TODO simply pass redis auth password in the env variable. should fetch from DB or manage server.
  if [ -z "$REDIS_AUTH" ]; then
    echo "error: please specify REDIS_AUTH $REDIS_AUTH"
    exit 2
  fi

  servers=""
  i=0
  for m in "${members[@]}"; do
    if [ "$i" = "0" ]; then
      servers="\"tcp:\/\/:$REDIS_AUTH@$m\""
    else
      servers+=",\"tcp:\/\/:$REDIS_AUTH@$m\""
    fi
    i=$(( $i + 1 ))
  done

  # update the servers in input conf
  sed -i "s/\"$FIRECAMP_SERVICE_SERVERS\"/$servers/g" $configDir/input_redis.conf

  # add service input plugin to telegraf.conf
  cat $configDir/input_redis.conf >> $configDir/telegraf.conf
fi

# add zookeeper input plugin
if [ "$MONITOR_SERVICE_TYPE" = "zookeeper" ]; then
  servers=""
  i=0
  for m in "${members[@]}"; do
    if [ "$i" = "0" ]; then
      servers="\"$m\""
    else
      servers+=",\"$m\""
    fi
    i=$(( $i + 1 ))
  done

  # update the servers in input conf
  sed -i "s/\"$FIRECAMP_SERVICE_SERVERS\"/$servers/g" $configDir/input_zk.conf

  # add service input plugin to telegraf.conf
  cat $configDir/input_zk.conf >> $configDir/telegraf.conf
fi

# add cassandra input plugin
if [ "$MONITOR_SERVICE_TYPE" = "cassandra" ]; then
  jolokiaPort="8778"
  servers=""
  i=0
  for m in "${members[@]}"; do
    if [ "$i" = "0" ]; then
      servers="\"$m:$jolokiaPort\""
    else
      servers+=",\"$m:$jolokiaPort\""
    fi
    i=$(( $i + 1 ))
  done

  casfile="$configDir/input_cas.conf"
  if [ -n "$MONITOR_METRICS" ]; then
    # custom metrics, update the input_cas_metrics.conf
    casfile="$configDir/input_cas_metrics.conf"
    # update metrics
    echo "$MONITOR_METRICS" >> $casfile
    echo "  ]" >> $casfile
  fi

  # update the servers in input conf
  sed -i "s/\"$FIRECAMP_SERVICE_SERVERS\"/$servers/g" $casfile

  # cassandra has a few system keyspaces, such as system, system_auth, system_schema. The system
  # keyspace and system_schema keyspace have many tables. Lots of metrics will get published.
  # TODO monitor table metrics for the user keyspaces.
  # TODO check and add the user keyspaces automatically.

  # add service input plugin to telegraf.conf
  cat $casfile >> $configDir/telegraf.conf
fi

# add output plugin
# Note: CloudWatch does not support delete metric, has to wait till it is automatically removed.
# CloudWatch metrics retention limits:
# - Data points with a period of 60 seconds (1 minute) are available for 15 days".
# - After 15 days this data is aggregated and is retrievable only with a resolution of 5 minutes. After 63 days, 1 hours.
# https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_concepts.html
cat $configDir/output_cloudwatch.conf >> $configDir/telegraf.conf

cat $configDir/telegraf.conf

echo "$@"
exec "$@"
