#!/bin/bash
#SBATCH -J name
#SBATCH -p queue
#SBATCH -t runtime
#SBATCH --mem=RAM
#SBATCH -N 1
#SBATCH -n hpctasks
#SBATCH -A account
vars
command
