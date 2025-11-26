# LakeSail (🦀)

taken from https://docs.lakesail.com/sail/latest/introduction/getting-started/

# Docker Image

We first need to build the Docker image for Sail. You can do this by running the following command in the `components/compute/sail/docker` directory:

```sh
docker build -t sail:0.4.2 --build-arg RELEASE_TAG="0.4.2" .
```

When running your cluster using kind:

```sh
kind load docker-image sail:latest --name local
```
