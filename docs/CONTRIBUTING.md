# Contributing guidelines

We are really glad you are seeing this and are considering contributing to the development of this tool.
We welcome any pull requests that help us grow as open source software!

## Submitting issues

Before submitting an issue, please verify there is not a similar one already listed.

## Development

Instructions on how to contribute code to this repository in the best way possible.

### Development environment

How to set up your development environment. For ease of use, consider using

#### Recommended tools

- UNIX-based operating system
- Python Interpreter v3.11
- Pip
- [Pycharm IDE](https://www.jetbrains.com/pycharm/)
- [Docker engine v24.0.0](https://docs.docker.com/engine/release-notes/24.0/#2400)
- [Docker compose v2.20](https://docs.docker.com/compose/release-notes/#2200)
- [Blaze store as a docker container](https://github.com/samply/blaze#docker)
- [BlazeCTL](https://github.com/samply/blazectl): a command line tool for interacting with a Blaze store
- [FHIR Test data generator](https://github.com/samply/bbmri-fhir-gen): a command line tool for generating FHIR test
  data
according to the [BBMRI.de FHIR profile](https://simplifier.net/bbmri.de).

#### Installing required packages

To install python packages using your system interpreter:

```shell
make setup
```
#### Docker image

Docker images are built continuously as part of the CI pipeline. However, for building your own test images simply
run: `docker build . -t ghcr.io/bbmri-eric/fhir-module:local` in the directory containing the `Dockerfile`.

#### Unit tests

To run unit tests:

```shell
make test
```
#### Integration tests

To run the integration tests:

```shell
make validate
```
### Commit messages

For git commit messages,
please follow the [Conventional Commits specification](https://www.conventionalcommits.org/en/v1.0.0/#summary).

### Submitting changes

Please send us a GitHub Pull Request with a clear description.

**Good luck and thank you! 🙇🏻‍♂️** ❤️