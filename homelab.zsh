#### Homelab aliases

# Sync homelab
alias hsync="/containers/homelab/scripts/sync-homelab.sh"
# Homelab status
alias hstatus="/containers/homelab/scripts/status-homelab.sh"
# Sync pihole DNS
alias hpihole="/containers/homelab/scripts/sync-pihole-dns.py"
# Restart homelab target
alias hrestart="systemctl --user restart homelab.target"
# Restart specific homelab service
alias hrestart-service="systemctl --user restart"
# View homelab journal logs
alias hjournal="journalctl -e --user-unit"
# Go to media directory
alias mcd="cd /bulk/media"
