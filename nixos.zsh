#### NixOS aliases

# Rebuild and switch to the new configuration
alias rb="nix flake update aliases --flake \$NIXOS_FLAKE && sudo nixos-rebuild switch --impure --flake \$NIXOS_FLAKE#\$(hostname)"
# Rebuild and test the new configuration (doesn't persist across reboot)
alias rbt="nix flake update aliases --flake \$NIXOS_FLAKE && sudo nixos-rebuild test --impure --flake \$NIXOS_FLAKE#\$(hostname)"
