{ pkgs, lib, config, ... }:

{
  packages = [
    pkgs.git
    # Build tools for native Node.js modules
    pkgs.gnumake
    pkgs.gcc
    pkgs.python3
  ];

  languages.javascript = {
    enable = true;
    package = pkgs.nodejs_22;
    corepack.enable = true;
    yarn = {
      enable = true;
      install.enable = true;
    };
  };

  processes = {
    backstage = {
      exec = "yarn dev";
    };
  };

  scripts = {
    build = {
      exec = "npx nx run-many -t build";
      description = "Build all packages with Nx caching";
    };
    build-backend = {
      exec = "yarn build:backend";
      description = "Build backend bundle for Docker";
    };
    docker-build = {
      exec = ''
        yarn tsc && yarn build:backend && \
        docker image build . -f packages/backend/Dockerfile --tag backstage:latest
      '';
      description = "Build Docker image";
    };
    docker-run = {
      exec = "docker run -it -p 7007:7007 backstage:latest";
      description = "Run Docker container";
    };
    nx-graph = {
      exec = "npx nx graph";
      description = "Visualize project dependency graph";
    };
  };

  enterShell = ''
    echo "=== Backstage Development Environment ==="
    echo "Node: $(node --version)"
    echo "Yarn: $(yarn --version)"
    echo ""
    echo "Available commands:"
    echo "  devenv up         - Start Backstage dev servers"
    echo "  yarn dev          - Start development servers directly"
    echo "  build             - Build all packages (Nx cached)"
    echo "  build-backend     - Build backend bundle"
    echo "  docker-build      - Build Docker image"
    echo "  docker-run        - Run Docker container"
    echo "  nx-graph          - Visualize dependencies"
  '';
}
