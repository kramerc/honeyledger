# Honeyledger

[![codecov](https://codecov.io/github/kramerc/honeyledger/graph/badge.svg?token=L03QSS837R)](https://codecov.io/github/kramerc/honeyledger)

## Setting up development environment

This project makes use of Dev Containers to provide a consistent development environment. To get started with [Visual Studio Code](https://code.visualstudio.com/):
1. Set up Docker with [Docker Desktop](https://docs.docker.com/get-started/introduction/get-docker-desktop/) (Windows/Linux/Mac) or with [Docker Engine](https://docs.docker.com/engine/install/) (Linux).
2. Set up Dev Containers in Visual Studio Code by following the [Dev Containers tutorial](https://code.visualstudio.com/docs/devcontainers/tutorial).
3. Clone the repo. On Windows, this should be done under [WSL](https://learn.microsoft.com/en-us/windows/wsl/install) for the best compatibility.
   ```
   git clone https://github.com/kramerc/honeyledger.git
   ```
4. Open the repo in Visual Studio Code:
   ```
   code honeyledger
   ```
5. Reopen the repo in Container. Visual Studio Code should prompt asking to do so. If it does not, open the Command Palette (`F1`) and run **Dev Containers: Reopen in Container**.

The container will take a few minutes to build for the first time. Once completed, everything should be ready to go.

## Running

The Rails development server can be started with:
```
bin/rails server
```

For assets, the Vite development can be started with:
```
bin/vite dev
```

Tests can be run with:
```
bin/rails test
```
