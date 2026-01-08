{ pkgs, lib, config, ... }:

{
  # OpenTelemetry environment variables for SDK auto-configuration
  # Apps using @opentelemetry/sdk-* will automatically send to local collector
  # Note: Using non-standard ports (4400/4401) to avoid conflict with system grafana-alloy on 4317/4318
  env = {
    OTEL_EXPORTER_OTLP_ENDPOINT = "http://localhost:4401";
    OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
    OTEL_SERVICE_NAME = "backstage-dev";
    OTEL_RESOURCE_ATTRIBUTES = "deployment.environment=development,service.namespace=backstage-dev";
  };

  # OpenTelemetry Collector - forwards telemetry to K8s observability stack
  # Receives: local apps on localhost:4400 (gRPC) / 4401 (HTTP) - non-standard to avoid grafana-alloy conflict
  # Exports: K8s otel-collector via port-forward on localhost:14317/14318
  # K8s collector routes to: Tempo (traces), Mimir (metrics), Loki (logs)
  services.opentelemetry-collector = {
    enable = true;
    settings = {
      receivers = {
        otlp = {
          protocols = {
            grpc.endpoint = "0.0.0.0:4400";
            http.endpoint = "0.0.0.0:4401";
          };
        };
      };

      processors = {
        batch = {
          timeout = "5s";
          send_batch_size = 1000;
        };
        resource = {
          attributes = [
            { key = "deployment.environment"; value = "development"; action = "insert"; }
            { key = "service.namespace"; value = "backstage-dev"; action = "insert"; }
          ];
        };
      };

      exporters = {
        # Forward to K8s OTEL collector via port-forward
        otlp = {
          endpoint = "localhost:14317";
          tls.insecure = true;
        };
        # Debug exporter for local troubleshooting
        debug = {
          verbosity = "basic";
        };
      };

      service = {
        pipelines = {
          traces = {
            receivers = [ "otlp" ];
            processors = [ "batch" "resource" ];
            exporters = [ "otlp" ];
          };
          metrics = {
            receivers = [ "otlp" ];
            processors = [ "batch" "resource" ];
            exporters = [ "otlp" ];
          };
          logs = {
            receivers = [ "otlp" ];
            processors = [ "batch" "resource" ];
            exporters = [ "otlp" ];
          };
        };
      };
    };
  };

  packages = [
    pkgs.git
    pkgs.jq
    pkgs.kubectl
    pkgs.psmisc  # Provides fuser for killing port processes
    pkgs.otel-cli  # For build instrumentation (traces/metrics to OTEL collector)
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

  # Development processes - run with 'devenv up'
  # Process-compose is the default process manager
  processes = {
    # Cleanup stale processes on OTEL ports before collector starts
    # Prevents "address already in use" errors from previous sessions
    otel-cleanup.exec = ''
      echo "Cleaning up stale OTEL ports..."
      fuser -k 4400/tcp 4401/tcp 2>/dev/null || true
      sleep 1
      echo "OTEL ports cleaned up"
    '';

    # Wait for port cleanup to complete before starting collector
    opentelemetry-collector.process-compose.depends_on.otel-cleanup.condition = "process_completed_successfully";

    # Port-forward K8s OTEL collector for local telemetry forwarding
    # Local OTEL collector (4400/4401) -> K8s OTEL collector (14317/14318)
    # K8s collector routes to: Tempo, Mimir, Loki
    otel-forward.exec = ''
      echo "Port-forwarding K8s OTEL collector..."
      echo "  Local collector:  localhost:4400 (gRPC) / 4401 (HTTP)"
      echo "  K8s collector:    localhost:14317 -> otel-collector.observability:4317"
      echo ""
      fuser -k 14317/tcp 14318/tcp 2>/dev/null || true
      exec kubectl port-forward -n observability svc/otel-collector 14317:4317 14318:4318
    '';

    # Backend in K8s via DevSpace - Clear stale state, then start dev mode
    # - Kill any process on port 7007 (stale port-forward)
    # - Delete devspace-dependencies ConfigMap (session lock)
    # - Reset pods (reverts to original image, keeps PVC)
    devspace.exec = ''
      fuser -k 7007/tcp 2>/dev/null || true
      kubectl delete configmap devspace-dependencies -n backstage 2>/dev/null || true
      devspace reset pods --force 2>/dev/null || true
      sleep 2
      exec devspace dev
    '';

    # Frontend with HMR - runs locally with webpack-dev-server
    # Waits for backend to be available before starting
    frontend.exec = ''
      echo "Waiting for K8s backend to be available..."
      until curl -ks https://backstage.cnoe.localtest.me:8443/.backstage/health/v1/readiness 2>/dev/null | grep -q '"status":"ok"'; do
        echo "  Backend not ready, waiting..."
        sleep 5
      done
      echo ""
      echo "Backend ready! Starting frontend with HMR..."
      echo "  Frontend: https://localhost:3000"
      echo "  Backend:  https://backstage.cnoe.localtest.me:8443/api"
      echo ""
      exec yarn workspace app start
    '';
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
    build-push = {
      exec = ''./scripts/build-push.sh "$@"'';
      description = "Build and push image to Gitea (use: build-push [--trigger-kargo] VERSION)";
    };
  };

  enterShell = ''
    echo "=== Backstage Development Environment ==="
    echo "Node: $(node --version)"
    echo "Yarn: $(yarn --version)"
    echo ""
    echo "Development Modes:"
    echo "  devenv up                    # Start all services (K8s backend + local frontend + OTEL)"
    echo "  yarn dev                     # Simple local dev (no K8s, no OTEL)"
    echo ""
    echo "K8s Development (with devenv up):"
    echo "  Frontend (HMR):  https://localhost:3000"
    echo "  Backend API:     https://backstage.cnoe.localtest.me:8443/api"
    echo "  devspace enter               # Shell into K8s dev container"
    echo "  devspace reset pods          # Revert to prod image (keeps node_modules)"
    echo "  devspace purge               # Full cleanup (deletes PVC)"
    echo ""
    echo "OpenTelemetry (auto-started with devenv up):"
    echo "  OTEL endpoint:   localhost:4400 (gRPC) / 4401 (HTTP)"
    echo "  K8s backends:    Tempo (traces), Mimir (metrics), Loki (logs)"
    echo "  View traces:     https://grafana.cnoe.localtest.me:8443/explore"
    echo ""
    echo "Build & Push:"
    echo "  build                        # Build all packages (Nx cached)"
    echo "  build-backend                # Build backend bundle"
    echo "  docker-build                 # Build Docker image"
    echo "  build-push VERSION [OPTIONS] # Build & push to Gitea"
    echo "    --trigger-kargo            # Trigger Kargo warehouse refresh"
    echo "  nx-graph                     # Visualize dependencies"
  '';
}
