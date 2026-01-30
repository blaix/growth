# A Pretty Nice Self-Improvement App

## Local development

This project uses Nix flakes for development and deployment.

```bash
# Run development services
nix run .#dev

# Enter development environment (provides gren, nodejs, etc.)
nix develop -c zsh # or your preferred shell

# Build the application package
nix build .#growth

# Test the locally-built package
./result/bin/growth
```

**Note:** You will need to `git add` files before they become visible to the build.
That's just how nix do.

See `flake.nix` for details.

## Deployment

This project has its own [flake](flake.nix) for its build and services, but is deployed to blaixapps via https://github.com/blaix/homer

```
cd ~/homer
just deploy-blaixapps
```

The homer flake stays pinned to a specific commit on main for reproducibility.
To update to the latest changes on main, update the homer flake lock file:

```
cd ~/homer
nix flake lock --update-input growth # or update everything with `nix flake update`
just deploy-blaixapps
```

To deploy the local copy instead of the version on github:

```
cd ~/homer
just deploy-blaixapps-local growth ~/projects/growth
```

To see where things are getting deployed on the server, run:

```
journalctl -u ws4sql-growth # to see database location
journalctl -u growth        # to see app deployment path
```

