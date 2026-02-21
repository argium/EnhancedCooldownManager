package = "enhancedcooldownmanager"
version = "1"

source = {
  url = "https://example.com/enhancedcooldownmanager",
}

description = {
  summary = "EnhancedCooldownManager addon dependency spec",
  detailed = "Dependency-only rockspec for local development and tests.",
  license = "GPL-3.0",
}

dependencies = {
  "lua >= 5.1",
  "moonscript",
  "busted",
}

build = {
  type = "none",
}
