env {
    SHELL = auto
    PATH += "~/.npm-global/bin"
}

if node.version < 18 {
    error "Node.js 18+ is required."
}

foreach package in packages {
    install package
}
