#### Homelab aliases

# Sync homelab
alias hsync="/containers/homelab/scripts/sync-homelab.sh"
# Homelab status
alias hstatus="/containers/homelab/scripts/status-homelab.sh"
# Sync pihole DNS
alias hpihole="/containers/homelab/scripts/sync-pihole-dns.py"
# Restart homelab target
alias hreboot="systemctl --user restart homelab.target"
# Restart specific homelab service
alias hrestart="systemctl --user restart"
# Start specific homelab service
alias hstart="systemctl --user start"
# Stop specific homelab service
alias hstop="systemctl --user stop"
# View homelab journal logs
alias hjournal="journalctl -e --no-pager --user-unit"
# Go to media directory
alias mcd="cd /bulk/media"
