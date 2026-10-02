# mise (https://mise.jdx.dev) switches language versions per project: Node,
# Python, Go and so on, from a project's mise.toml or .tool-versions. Turn it
# on in interactive bash; nothing changes until a project or `mise use` asks.
if [ -n "${BASH_VERSION-}" ] && [ -n "${PS1-}" ] && command -v mise >/dev/null; then
	eval "$(mise activate bash)"
fi
