# nx-backstage

A [Backstage](https://backstage.io) developer portal with Nx build optimization and devenv for reproducible development environments.

## Prerequisites

- [Nix](https://nixos.org/download.html) with flakes enabled
- [devenv](https://devenv.sh/getting-started/)
- [direnv](https://direnv.net/) (optional, for automatic environment activation)

## Getting Started

### Enter Development Environment

```sh
devenv shell
```

This provides Node.js 22, Yarn 4.4.1, and all required build tools.

### Start Development Servers

```sh
yarn dev
```

- Frontend: http://localhost:3000
- Backend: http://localhost:7007

### Available Commands

| Command | Description |
|---------|-------------|
| `devenv up` | Start Backstage via process manager |
| `yarn dev` | Start frontend and backend |
| `build` | Build all packages (Nx cached) |
| `build-backend` | Build backend bundle for Docker |
| `docker-build` | Build Docker image |
| `docker-run` | Run Docker container |
| `nx-graph` | Visualize dependency graph |

## Build Optimization

This project uses [Nx](https://nx.dev) for build caching and optimization:

- Local caching enabled for build, test, lint, and tsc tasks
- Remote caching via Nx Cloud for CI and team collaboration
- Run `npx nx run-many -t build` to build all packages with caching

## Docker Deployment

Build the backend Docker image:

```sh
yarn tsc
yarn build:backend
docker image build . -f packages/backend/Dockerfile --tag backstage:latest
```

Run the container:

```sh
docker run -it -p 7007:7007 backstage:latest
```

## Project Structure

```
.
├── packages/
│   ├── app/          # Frontend React app
│   └── backend/      # Backend Node.js service
├── plugins/          # Custom Backstage plugins
├── devenv.nix        # Development environment config
├── nx.json           # Nx workspace config
└── app-config.yaml   # Backstage configuration
```

## CI/CD

GitHub Actions workflow runs on push/PR to main:
- Type checking, linting, testing
- Build with Nx caching
- Docker image build

Nx Cloud provides remote caching for faster CI builds.
