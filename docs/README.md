# Tools Setup

## Busted

```sh
# Install lua and luarocks, then:

luarocks install --local moonscript busted luacheck

# Run all tests
busted Tests

# Run ECM-specific tests only
busted -r ecm Tests

# Run LibSettingsBuilder tests only
busted -r libsettingsbuilder Tests
```
