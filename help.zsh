help() {
  # Display all custom aliases and functions (only those prefixed with 'function') from sourced alias files
  # Supports both NixOS (/etc/zshenv + ALIASES_DIR) and macOS (~/.zshrc + ~/.config/aliases + ~/.config/aliases-private)

  local zshrc aliases_dir aliases_dir_private
  if [[ -n "$ALIASES_DIR" ]]; then
    zshrc="/etc/zshenv"
    aliases_dir="$ALIASES_DIR"
    aliases_dir_private=""
  else
    zshrc="$HOME/.zshrc"
    aliases_dir="$HOME/.config/aliases"
    # On macOS, also check for private aliases
    if [[ -d "$HOME/.config/aliases-private" ]]; then
      aliases_dir_private="$HOME/.config/aliases-private"
    else
      aliases_dir_private=""
    fi
  fi

  # Colors
  local cyan='\033[36m'
  local yellow='\033[33m'
  local dim='\033[2m'
  local reset='\033[0m'

  # Find all sourced aliases files
  local sourced_files=()
  while IFS= read -r line; do
    # Match: source <path>/filename.zsh where path contains the aliases directory
    if [[ $line =~ 'source[[:space:]]+([^[:space:]]+\.zsh)' ]]; then
      local file="${match[1]}"
      # Check if the file is in our aliases directory (public or private)
      if [[ "$file" == "$aliases_dir"/* ]] || [[ "$file" == '~/.config/aliases'/* ]] || [[ "$file" == '$HOME/.config/aliases'/* ]] \
         || ( [[ -n "$aliases_dir_private" ]] && [[ "$file" == "$aliases_dir_private"/* ]] ) \
         || [[ "$file" == '~/.config/aliases-private'/* ]] || [[ "$file" == '$HOME/.config/aliases-private'/* ]]; then
        # Expand the path if needed
        [[ "$file" == '~'* ]] && file="${file/#\~/$HOME}"
        [[ "$file" == '$HOME'* ]] && file="${file/\$HOME/$HOME}"
        sourced_files+=("$file")
      fi
    fi
  done < "$zshrc"

  echo ""
  echo "${cyan}Custom Aliases & Functions${reset}"
  echo "${cyan}──────────────────────────${reset}"

  for file in "${sourced_files[@]}"; do
    [[ -f "$file" ]] || continue

    # Use filename (without .zsh) as category, prettify it
    local category="${file:t:r}"
    category="${category//_/ }"                        # Replace underscores with spaces
    category="${(C)category}"                          # Capitalize words
    category="${category/Aws/AWS}"                     # Fix AWS acronym
    category="${category/Github/GitHub}"               # Fix GitHub casing
    local prev_comment=""
    local -A items=()
    local max_name_len=0

    while IFS= read -r line; do
      # Capture comment lines (potential descriptions)
      if [[ $line =~ '^#[[:space:]]*(.*)' ]]; then
        prev_comment="${match[1]}"
        continue
      fi

      # Match function definitions with 'function' keyword only, skipping
      # underscore-prefixed helpers that aren't meant to be called directly
      if [[ $line =~ '^function[[:space:]]+([a-zA-Z][a-zA-Z0-9_]*)' ]]; then
        local name="${match[1]}"
        items[$name]="$prev_comment"
        (( ${#name} > max_name_len )) && max_name_len=${#name}
        prev_comment=""
        continue
      fi

      # Match alias definitions
      if [[ $line =~ '^alias[[:space:]]+([^=]+)=' ]]; then
        local name="${match[1]}"
        items[$name]="$prev_comment"
        (( ${#name} > max_name_len )) && max_name_len=${#name}
        prev_comment=""
        continue
      fi

      # Reset comment if line is not a comment, function, or alias
      prev_comment=""
    done < "$file"

    # Print category if it has items
    if (( ${#items} > 0 )); then
      echo ""
      echo "${cyan}▸ ${category}${reset}"
      local padding=$((max_name_len + 2))
      for key in $(printf '%s\n' "${(k)items[@]}" | sort); do
        printf "  ${yellow}%-${padding}s${reset} ${dim}%s${reset}\n" "$key" "${items[$key]}"
      done
    fi
  done
  echo ""
}
