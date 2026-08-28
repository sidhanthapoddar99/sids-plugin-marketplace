// The one config loader. Reads the user config file, overlays <PROJECT>_* env, validates into Config.
// Holds api_url and the token path. Never a secret in the file; the token lives in the OS keyring.
package config
