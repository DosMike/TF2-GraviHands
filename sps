#!/bin/bash
# check if java is installed
if ! which java >nul ; then
  echo 'Could not find Java - SPSauce requires Java 8+'
  echo 'Please install an OpenJDK package (openjdk-8-jre)'
  echo ''
  exit 1
fi
# check if git is installed - depedency clone will try to use system git
if ! which git >nul ; then
  echo 'Could not find git - Some dependencies might fail!'
  echo 'Please install the git package (git)'
  echo ''
fi
# search for the jar file relative to this script
scriptDir=$PWD
cd ${0%/*}
fname="$PWD/spsauce/"$(ls -r1A spsauce | grep '^SPSauce-.*\.jar$' | head -n1)
cd $scriptDir
# run the jar file from the spsauce directory
if [[ -f $fname ]]; then
  java -jar $fname $@
else
  echo 'Could not find any SPSauce jar binary'
fi
