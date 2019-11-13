#!/usr/bin/env bash
#sudo apt-get install -y shellcheck

shellcheck -x -e SC2086,SC2126 CLV_Automl.sh

if [ $? -eq 0 ]
then
  git add .;git commit -m "$1";git push
fi
