# LakeSail (🦀)

taken from https://docs.lakesail.com/sail/latest/introduction/getting-started/

# Docker Image

We first need to build the Docker image for Sail. You can do this by running the following command in the `components/compute/sail/docker` directory:

```bash
docker build -t sail:latest --build-arg RELEASE_TAG="v0.4.1" .
```
