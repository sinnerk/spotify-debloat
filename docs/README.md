# Documentation

Start with the project [README](../README.md) for install and commands, then pick the
document that matches your question.

| Document | Read it when |
| --- | --- |
| [ARCHITECTURE.md](ARCHITECTURE.md) | You want to understand how the module, state file and install pipeline fit together, or you are changing the code. |
| [DEBLOAT.md](DEBLOAT.md) | You want to know exactly which setting or flag does what, and what is deliberately not done. |
| [PLUGINS.md](PLUGINS.md) | You want to install something that is not in a preset, understand the catalog, or write your own preset. |
| [BENCHMARKS.md](BENCHMARKS.md) | You want the measured cost of the theme and the extensions, and how to reproduce it. |
| [SAFETY.md](SAFETY.md) | You want to know what is written to disk, how to undo it, and what the supply-chain risk is. |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Something broke. Start with `.\lean.ps1 doctor`. |
| [MAINTAINING.md](MAINTAINING.md) | Spotify or Spicetify updated, or you are refreshing the catalog and the benchmarks. |

## Conventions used here

* Paths are given with Windows environment variables (`%APPDATA%`, `%LOCALAPPDATA%`)
  rather than absolute paths, so they stay correct on any machine.
* Commands are Windows PowerShell. PowerShell 7 works everywhere unless a document says
  otherwise.
* "Extension" means a Spicetify extension (JavaScript loaded into the client). "App" means
  a Spicetify custom app (its own page in the sidebar). "Snippet" means a CSS fragment.
* Percentages of CPU are always **percent of one core**, never percent of the machine.
