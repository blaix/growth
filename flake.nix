{
  description = "Growth - A pretty nice self-improvement app";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ws4sql.url = "path:./nixpkgs/ws4sql";
    process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";
  };

  outputs = { self, nixpkgs, ws4sql, process-compose-flake }:
    let
      # Support both Mac (development) and Linux (production)
      supportedSystems = [ "x86_64-linux" "aarch64-darwin" ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      pkgsFor = system: nixpkgs.legacyPackages.${system};

      mkGrowthPackage = system:
        let
          pkgs = pkgsFor system;
          gren = pkgs.gren;
        in
        pkgs.stdenv.mkDerivation {
          pname = "growth";
          version = "0.0.1";
          src = ./.;

          buildInputs = [
            gren
            pkgs.nodejs
          ];

          buildPhase = ''
            ${gren}/bin/gren make Main
          '';

          installPhase = ''
            mkdir -p $out/share/growth/public
            cp app $out/share/growth/
            cp -r public/* $out/share/growth/public/

            # Create wrapper script
            mkdir -p $out/bin
            cat > $out/bin/growth <<EOF
#!/bin/sh
cd $out/share/growth
exec ${pkgs.nodejs}/bin/node app "\$@"
EOF
            chmod +x $out/bin/growth
          '';
        };
    in
    {
      # Packages for all systems
      packages = forAllSystems (system: {
        growth = mkGrowthPackage system;
        ws4sql = ws4sql.packages.${system}.default;
        default = mkGrowthPackage system;
      });

      # Development services (process-compose-flake) for all systems
      process-compose = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          growth-package = mkGrowthPackage system;
        in
        {
          dev.settings.processes = {
            db = {
              command = ''
                mkdir -p ./data
                echo "Database: ./data/growth.db"
                ${ws4sql.packages.${system}.default}/bin/ws4sql --quick-db ./data/growth.db
              '';
              ready_log_line = "Web Service listening"; # Output that means service is ready.
            };

            server = {
              command = ''
                echo "App deployed at: ${growth-package}/share/growth"
                ${pkgs.nodejs}/bin/node ${growth-package}/share/growth/app
              '';
              working_dir = "${growth-package}/share/growth";
              depends_on.db.condition = "process_log_ready"; # Waits for output from ready_log_line above.
            };
          };
        }
      );

      # Development shell for all systems
      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            buildInputs = [
              pkgs.gren
              pkgs.nodejs
              pkgs.fd
              ws4sql.packages.${system}.default
            ];

            shellHook = ''
              echo ""
              echo "=================================================="
              echo "Welcome to the growth development environment."
              echo "Run 'nix run .#dev' to start services."
              echo "Run 'nix build .#growth' to build the package."
              echo "=================================================="
            '';
          };
        }
      );

      # Apps for running development services
      apps = forAllSystems (system:
        let
          pkgs = pkgsFor system;
          # Convert process-compose config to YAML
          processComposeConfig = pkgs.writeText "process-compose.yaml"
            (builtins.toJSON self.process-compose.${system}.dev.settings);
          startScript = pkgs.writeShellScript "start-dev" ''
            # If running in a terminal, use TUI mode, otherwise use log mode
            if [ -t 0 ]; then
              exec ${pkgs.process-compose}/bin/process-compose up -f ${processComposeConfig} --keep-project
            else
              exec ${pkgs.process-compose}/bin/process-compose up -f ${processComposeConfig} --tui=false
            fi
          '';
        in
        {
          dev = {
            type = "app";
            program = "${startScript}";
          };
        }
      );

      # Production NixOS module (Linux only)
      nixosModules.growth = { config, lib, pkgs, ... }:
        with lib;
        let
          cfg = config.services.growth;
          # Use x86_64-linux for the production module
          system = "x86_64-linux";
          growth-package = mkGrowthPackage system;
        in
        {
          options.services.growth = {
            enable = mkEnableOption "Enable growth app service";

            domain = mkOption {
              type = types.str;
              description = "Domain name for the application";
            };

            acmeEmail = mkOption {
              type = types.str;
              description = "Email address for ACME/Let's Encrypt";
            };

            enableBackups = mkOption {
              type = types.bool;
              default = true;
              description = "Enable automatic daily backups";
            };

            dataDir = mkOption {
              type = types.path;
              default = "/var/lib/growth";
              description = "Directory for application data";
            };

            appPort = mkOption {
              type = types.int;
              default = 3000;
              description = "Port for the Node.js application";
            };

            ws4sqlPort = mkOption {
              type = types.int;
              default = 12321;
              description = "Port for the ws4sql database server";
            };

            basicAuth = {
              enable = mkEnableOption "Enable HTTP Basic authentication";

              htpasswdFile = mkOption {
                type = types.path;
                default = "/etc/htpasswd";
                description = "Path to htpasswd file for HTTP Basic auth";
              };
            };
          };

          config = mkIf cfg.enable {
            # ws4sql database service
            systemd.services.ws4sql-growth = {
              description = "ws4sql database server for growth";
              wantedBy = [ "multi-user.target" ];

              serviceConfig = {
                ExecStartPre = "${pkgs.coreutils}/bin/echo 'Database: ${cfg.dataDir}/growth.db'";
                ExecStart = "${ws4sql.packages.${system}.default}/bin/ws4sql -port ${toString cfg.ws4sqlPort} --quick-db ${cfg.dataDir}/growth.db";
                DynamicUser = true;
                StateDirectory = "growth";
                Restart = "always";
                RestartSec = "5s";
              };
            };

            # growth application service
            systemd.services.growth = {
              description = "Growth application";
              wantedBy = [ "multi-user.target" ];
              after = [ "ws4sql-growth.service" "network-online.target" ];
              wants = [ "network-online.target" ];
              requires = [ "ws4sql-growth.service" ];

              serviceConfig = {
                ExecStartPre = "${pkgs.coreutils}/bin/echo 'App deployed at: ${growth-package}/share/growth'";
                ExecStart = "${pkgs.nodejs}/bin/node ${growth-package}/share/growth/app --port ${toString cfg.appPort} --ws4sql-port ${toString cfg.ws4sqlPort}";
                WorkingDirectory = "${growth-package}/share/growth";
                DynamicUser = true;
                User = "growth";
                Restart = "always";
                RestartSec = "5s";
              };
            };

            # Optional backup service
            systemd.services.growth-backup = mkIf cfg.enableBackups {
              description = "Backup growth database";
              serviceConfig = {
                Type = "oneshot";
                ExecStart = pkgs.writeShellScript "growth-backup" ''
                  mkdir -p ${cfg.dataDir}/backups
                  ${pkgs.sqlite}/bin/sqlite3 ${cfg.dataDir}/growth.db ".backup ${cfg.dataDir}/backups/growth-$(date +%Y%m%d-%H%M%S).db"
                  find ${cfg.dataDir}/backups -name "growth-*.db" -mtime +60 -delete
                '';
                User = "growth";
                DynamicUser = true;
                StateDirectory = "growth";
              };
            };

            systemd.timers.growth-backup = mkIf cfg.enableBackups {
              description = "Backup timer for growth (daily)";
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = "daily";
                Persistent = true;
              };
            };

            # Nginx reverse proxy
            services.nginx = {
              enable = true;
              recommendedProxySettings = true;
              recommendedTlsSettings = true;
              recommendedOptimisation = true;
              recommendedGzipSettings = true;

              virtualHosts.${cfg.domain} = {
                enableACME = true;
                forceSSL = true;
                http2 = false;  # Disable HTTP/2 to enable WebSocket upgrades
                # Auth handled by app (token-based)

                locations."/" = {
                  proxyPass = "http://127.0.0.1:${toString cfg.appPort}";
                  proxyWebsockets = true;  # Allow WebSocket upgrades to pass through to server.js
                } // lib.optionalAttrs cfg.basicAuth.enable {
                  basicAuthFile = cfg.basicAuth.htpasswdFile;
                };
              };
            };

            # ACME configuration
            security.acme = {
              acceptTerms = true;
              defaults.email = cfg.acmeEmail;
            };
          };
        };

      nixosModules.default = self.nixosModules.growth;
    };
}
