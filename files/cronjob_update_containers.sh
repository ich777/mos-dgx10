#!/bin/bash
docker pull ghcr.io/ggml-org/llama.cpp:server-cuda13
docker pull ghcr.io/leejet/stable-diffusion.cpp:master-cuda-spark
sleep 2
docker image prune -f
