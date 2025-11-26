# LakeSail (🦀)

taken from https://docs.lakesail.com/sail/latest/introduction/getting-started/

# Docker Image

We first need to build the Docker image for Sail. You can do this by running the following command in the `components/compute/sail/docker` directory:

```sh
# 1. Build the image (Compiles Rust from source)
# Be sure to use the 'v' prefix if the git tags have it (they usually do)
docker build -t sail:latest \
  --build-arg RELEASE_TAG="v0.4.2" \
  .

# 2. Load into Kind (Required so K8s can find "sail:latest")
kind load docker-image sail:latest --name local
```
