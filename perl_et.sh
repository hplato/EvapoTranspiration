#!/bin/bash
export DIR=$(dirname "$0")
echo "DIR: $DIR"
DIR=${PWD-$DIR}
if [ "${DIR}" = "." ]; then
    DIR=${PWD}
fi
echo "DIR: $DIR"

#echo Calculating values. Logging to /var/log/mh/scripts/WeatherCustom.log
echo Calculating values. Logging to ${DIR}/perl/logs/WeatherCustom.log

perl $DIR/perl/weatherCustom.pl $DIR/perl/logs $DIR/perl/ET $DIR/perl/wuData $DIR/perl/weatherprograms $1 2>&1 | tee $DIR/perl/logs/weatherCustom.log
