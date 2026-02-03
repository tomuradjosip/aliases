#### Core aliases

# Open the aliases repository in Cursor
alias ea="cursor ~/.config/aliases"
# Source the zshrc file
alias sa="exec zsh"

# Open the chezmoi directory in Cursor
alias ce="cursor ~/.local/share/chezmoi"
# Apply the chezmoi changes
alias ca="chezmoi apply && exec zsh"

# SSH add the GitHub key
alias creds="ssh-add -D; ssh-add ~/.ssh/id_github"

# Run pre-commit
alias pre="pre-commit run -a"

# ls aliases
# Long format, all including hidden
alias l='ls -lah --color=auto'
# Long format, no hidden
alias ll='ls -lh --color=auto'
# Long format, all including hidden except . and ..
alias la='ls -lAh --color=auto'

# Display all custom aliases and functions from sourced zsh.d files
alias h="help"
