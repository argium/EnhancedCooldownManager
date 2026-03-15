# Tools Setup

## Busted

```sh
# Install lua and luarocks, then:

luarocks install moonscript busted luacheck

# Run all tests
busted Tests

# Run ECM-specific tests only
busted -r ecm Tests

# Run LibSettingsBuilder tests only
busted -r libsettingsbuilder Tests
```

Coverage reports are generated in GitHub Actions, including an HTML artifact (`luacov-html-report`).
