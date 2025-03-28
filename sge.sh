#!/bin/bash
#$ -N name
#$ -q queue
#$ -l h_rt=runtime
#$ -l mem_free=RAM
#$ -pe smp hpctasks
#$ -cwd
#$ -P account
##$ -S /bin/bash #smrt.q only?
vars
command
