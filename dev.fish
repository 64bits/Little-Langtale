#!/opt/homebrew/bin/fish
docker run --rm -it -v ./app/:/app/ --network="host" --entrypoint=/bin/bash little-langtale