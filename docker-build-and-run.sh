#!/bin/bash

if [ "$1" = '-p' ]; then
	docker compose pull
fi

docker compose up -d --remove-orphans
