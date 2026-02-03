#### NixOS aliases

# Rebuild and switch to the new configuration
alias rb="nix flake update aliases --flake \$HOME/nixosconfig && sudo nixos-rebuild switch --impure --flake \$HOME/nixosconfig#\$(hostname)"
# Rebuild and test the new configuration (doesn't persist across reboot)
alias rbt="nix flake update aliases --flake \$HOME/nixosconfig && sudo nixos-rebuild test --impure --flake \$HOME/nixosconfig#\$(hostname)"
