#!/bin/bash

TAG=$1

time docker build -t swiclops:$TAG . &&
docker tag swiclops:$TAG gitlab.futo.org:5050/cvwright/swiclops:$TAG &&
docker tag swiclops:$TAG gitlab.futo.org:5050/cvwright/swiclops:latest &&
docker push gitlab.futo.org:5050/cvwright/swiclops 
date

