#!/bin/bash
# Small wrapper for SGLBackup to create Oracle Backups via CRON and have also the required
# environment settings correctly set before starting the script.
# Example cron entry:
# 46 11 * * * cd /export/home/siegel/SGLBackup; ./orawrapper.sh --backupset=10,11 >/dev/null
###################################################################################################
# $Id: orawrapper.sh 2 2011-05-24 12:06:30Z siegel $
###################################################################################################

SGLBACKUP=./SGLBackup.pl
CONFIG=./ebola_oracle.ini

###################################################################################################
# First source the Oracle environment variables:

export ORACLE_BASE=/opt/oracle
export ORACLE_HOME=$ORACLE_BASE/product/10gR2
export ORACLE_DOC=$ORACLE_BASE/documentation
export ORA_NLS33=$ORACLE_HOME/ocommon/nls/admin/data
export ORACLE_SID=EBOLA
export NLS_LANG=AMERICAN_AMERICA.UTF8

# Now start the script and pass all parameters given to this script directly to SGLBackup:

$SGLBACKUP --config=$CONFIG $1

# EOF
