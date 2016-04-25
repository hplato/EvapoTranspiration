#!/bin/bash
export DIR=$(dirname "$0")
echo "DIR: $DIR"
DIR=${PWD-$DIR}
if [ "${DIR}" = "." ]; then
    DIR=${PWD}
fi
echo "DIR: $DIR"

#echo Calculating values. Logging to /var/log/mh/scripts/WeatherCustom.log
echo Calculating values. Logging to ${DIR}/python/logs/WeatherCustom.log

python $DIR/python/weatherCustom.py $DIR/python/logs $DIR/python/ET $DIR/python/wuData $DIR/python/weatherprograms $1 2>&1 | tee $DIR/python/logs/weatherCustom.log
