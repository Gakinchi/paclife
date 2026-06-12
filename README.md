# ⚡ PacLife

> **All Eyez on your environment.**

A persistent **Power Platform CLI (`pac`) statusline** pinned to the top of your terminal.
Always know **who** you're logged in as, **which tenant**, **which environment**, and **which solution**
you're working on — before you run that `pac solution import` against the wrong org.

```
 ⚡ PacLife  dennis@contoso.com  Contoso Prod ⚠ Production  EMEA  4 profiles  pac 2.7.4
┌──────────────────────────────────────────────────────────────────────┐
│  ↑ pinned to row 1 — your commands and output scroll freely below    │
│                                                                      │
│  PS> pac env select --environment contoso-dev                        │
│  PS> _            ← the statusline switched environment automatically │
└──────────────────────────────────────────────────────────────────────┘
```

Named after 2Pac's *Pac's Life*. Yes, really.

## Why

- `pac org who` takes **6+ seconds** (network round-trip). PacLife reads pac's **local auth store**
  and renders in **milliseconds** — no network calls, ever.
- The statusline **refreshes after every command**: run `pac auth select` or `pac env select`
  and the top row updates immediately.
- **Production gets the red treatment**: environments of type `Production`/`Default` — or any URL
  you mark as protected — show a red segment stating why: `⚠ Production`, `⚠ Default Environment`
  or `⚠ Protected`.
- **Service principals are unmistakable**: SPN auth renders on a purple segment with the AppId,
  so a CI/consultant identity is never mistaken for you.
- **Sovereign clouds stand out**: GCC / GCC High / DoD / China get a high-visibility magenta segment.

## Install

```powershell
irm https://raw.githubusercontent.com/Gakinchi/power-platform-cli-environment-banner/main/install.ps1 | iex
```

Installs the latest [GitHub Release](https://github.com/Gakinchi/power-platform-cli-environment-banner/releases)
into your user module path and adds an activation block to your PowerShell profile.

**Requirements:** a VT-capable terminal (Windows Terminal, VS Code terminal, iTerm2, ...).
Works on both PowerShell 7+ and Windows PowerShell 5.1 — it's the terminal that matters, not the shell.
In a legacy console without VT support, PacLife simply stays quiet.

## Commands

| You type | Which is | What it does |
|---|---|---|
| `paclife` | `Show-PacLife` | print the compact context line once |
| `alleyez` | `Show-PacLife -Full` | *All Eyez on Me* — the full detail banner |
| `keepyaheadup` | `Enable-PacLife` | pin the statusline to the top (+ profile) |
| `lifegoeson` | `Disable-PacLife` | turn it off and restore the terminal |
| `changes` | `Update-PacLife` | update to the latest release |
| | `Get-PacContext` | the context as an object, for your own scripts |

## What the statusline shows

| Segment | Source |
|---|---|
| Identity | user UPN (blue) or service principal AppId (purple, `SPN`) |
| Environment | friendly name, colored **red** (Production/Default/protected), **green** (Sandbox/Developer/Trial), **yellow** (unknown or *no environment selected*) |
| Auth kind | only shown for legacy `DATAVERSE`/`ADMIN` profiles (explains why some pac commands fail despite being "logged in") — the modern `UNIVERSAL` default is hidden |
| Geo / cloud | the environment's region (`EMEA`, dim); the cloud appears only when sovereign (`GCC High`, magenta) — the default `Public` cloud is hidden |
| Solution | detected from your working directory (`.cdsproj`, `src/Other/Solution.xml`, `.pcfproj` — searched upward, like git finds `.git`) |
| Profiles | `4 profiles` — shown when you have more than one to switch between (`pac auth list`; details in `alleyez`) |
| pac version | the locally installed CLI version |

The terminal **tab title** is set to the environment name too, so you can tell your tabs apart.

## Matches your oh-my-posh theme

If you use [oh-my-posh](https://ohmyposh.dev), PacLife reads your active theme
(via `POSH_THEME`, offline — it never runs `oh-my-posh.exe`) and restyles itself to match:

- **Colors**: segments adopt your theme's palette, rendered in exact 24-bit truecolor.
- **Shape**: diamond-style themes (like *atomic*) get diamond-capped segments;
  powerline themes get their own separator glyph.
- **Semantics stay sacred**: the environment segment keeps its red/green/yellow meaning,
  but uses *your theme's own* red/green/yellow shades (with built-in fallback when the
  theme has no matching hue). Theme matching changes nuances, never meaning.

JSON themes only — YAML/TOML themes silently fall back to the built-in palette.
Set `"theme": "builtin"` to opt out.

## Configuration (`~/.paclife.json`, optional)

```json
{
  "protectedUrls": ["*contoso-prod*", "*.crm4.dynamics.com/"],
  "safeUrls": ["*playground*"],
  "windowTitle": true,
  "theme": "auto",
  "style": "auto"
}
```

- `protectedUrls` — wildcard patterns that force the red treatment regardless of environment type
  (for that production org someone created as a *Sandbox*...). `safeUrls` mutes it.
- `theme` — `"auto"` (match oh-my-posh when present), `"builtin"`, or a path to an `.omp.json` file.
- `style` — `"auto"` (follow the theme), `"powerline"`, `"diamond"`, or `"plain"`.
- `NO_COLOR` environment variable is honored.

## Honesty notes (by design)

- PacLife shows the **last known context** — a mirror of what pac last wrote to disk.
  It never claims live status and never makes a network call (only `changes`/`install.ps1` touch
  the network, because you asked them to).
- The *"context last refreshed ≈ ..."* line in `alleyez` is derived from the cached token timestamp.
  An old date does **not** mean you must re-authenticate — pac renews tokens silently.
- **Logged in ≠ connected to an environment.** If you're authenticated without an environment,
  PacLife says so on a yellow segment instead of pretending.

## Using oh-my-posh or starship?

No problem — PacLife *wraps* your prompt function and calls it through, so both render.
Just make sure the PacLife block stays **last** in your `$PROFILE` (the installer puts it there).

## Uninstall

```powershell
lifegoeson    # turn off + remove from profile
# or remove everything:
irm https://raw.githubusercontent.com/Gakinchi/power-platform-cli-environment-banner/main/uninstall.ps1 | iex
```

## FAQ

**Why doesn't it show whether my token is still valid?**
Because it can't know without a network call, and a statusline that makes network calls on every
prompt is a statusline you'll uninstall by lunch. See *Honesty notes*.

**The top row got messed up by a full-screen app (vim, less).**
It heals on your next prompt — the scroll region and statusline are re-asserted every time.

**Does it send telemetry?**
No.

## License

MIT — see [LICENSE](LICENSE).
