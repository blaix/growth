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

This project has its own [flake](flake.nix) for its build and services, but doesn't handle server provisioning on its own.

My copy is deployed to my personal server via https://github.com/blaix/homer.
The deployment process looks like this:

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

### Password-protection

The nix flake includes an option for HTTP Basic auth.
If enabled, you'll need to do this one-time server setup to create the password file:

```
nix-shell -p apacheHttpd --run "htpasswd -c /var/lib/growth/htpasswd <username>"
```

You'll be prompted to enter and confirm the password.

## Distribution and Copyright

This is Free Software. All files in this repository are Copyright 2024-present Justin Blake and distributed without warranty under the terms of the GNU Affero General Public License.

This means you can copy, fork, use, modify, and distribute this code however you want, even for commercial purposes, as long as you make the code, including your modifications, available under these same terms to anyone who uses it. This applies even if they are using it as a web app or service over a network.
