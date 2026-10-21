typeset -U path
path=(~/.local/bin $path)

HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
setopt share_history hist_ignore_all_dups hist_ignore_space hist_reduce_blanks hist_fcntl_lock AUTO_CD EXTENDED_GLOB

autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
if command -v dircolors >/dev/null 2>&1; then
    eval "$(dircolors -b)"
    zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
fi

bindkey -e
bindkey '^[[H' beginning-of-line;  bindkey '^[OH' beginning-of-line
bindkey '^[[F' end-of-line;        bindkey '^[OF' end-of-line
bindkey '^[[3~' delete-char
bindkey '^[[1;5C' forward-word;    bindkey '^[[1;5D' backward-word
bindkey '^[[3;5~' kill-word;       bindkey '^H' backward-kill-word
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search; zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search;  bindkey '^[OA' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search; bindkey '^[OB' down-line-or-beginning-search

autoload -Uz vcs_info add-zsh-hook
zstyle ':vcs_info:git:*' formats ' %F{magenta}(%b)%f'
add-zsh-hook precmd vcs_info
setopt prompt_subst
PROMPT='%F{green}%n@%m%f %F{blue}%~%f${vcs_info_msg_0_} %(?..%F{red}[%?]%f )%# '

if command -v eza >/dev/null 2>&1; then
    alias ls='eza --icons=auto --group-directories-first'
    alias ll='eza -l --icons=auto --git --group-directories-first --time-style=long-iso'
    alias la='eza -la --icons=auto --git --group-directories-first --time-style=long-iso'
    alias lt='eza --tree --level=2 --icons=auto --group-directories-first'
fi
if command -v bat >/dev/null 2>&1; then
    alias cat='bat --paging=never --style=plain'
elif command -v batcat >/dev/null 2>&1; then
    alias bat='batcat'
    alias cat='batcat --paging=never --style=plain'
fi
if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
    alias fd='fdfind'
fi
alias up='sudo ogust up'

command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
[[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
