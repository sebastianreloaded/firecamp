#!/bin/bash
set -e

# see supported platforms and db types in types.go
#CONTAINER_PLATFORM="ecs"
#DB_TYPE="clouddb"

if [ -z "$CONTAINER_PLATFORM" ] || [ -z "$DB_TYPE" ] || [ -z "$AVAILABILITY_ZONES" ]
then
  echo "error: please input all required environment variables" >&2
  echo "CONTAINER_PLATFORM $CONTAINER_PLATFORM, DB_TYPE $DB_TYPE, AVAILABILITY_ZONES $AVAILABILITY_ZONES" >&2
  exit 1
fi

exec "/firecamp-manageserver" "-container-platform=$CONTAINER_PLATFORM" "-dbtype=$DB_TYPE" "-availability-zones=$AVAILABILITY_ZONES"
