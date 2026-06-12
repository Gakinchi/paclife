# PacLife — domain glossary

PacLife is a persistent Power Platform CLI statusline for the terminal, named after 2Pac's *Pac's Life*.

- **Last known context** — the snapshot `pac` last wrote to its local auth store
  (`authprofiles_v2.json`). PacLife is a *mirror* of this store: it never claims live
  status and never makes network calls.
- **Context freshness** — derived from the active profile's `ExpiresOn`
  (≈ the last time pac performed an authenticated call). Informational only;
  never worded as a token or authentication warning. An "expired" `ExpiresOn` does
  **not** mean re-auth is required — MSAL refresh tokens renew silently.
- **Logged in ≠ connected to an environment** — an auth profile may exist without an
  environment (`Resource` missing or non-Dataverse). Two distinct states, never
  conflated. No-environment is an explicit yellow state ("run `pac env select`").
- **Protected environment** — an environment that gets the red treatment.
  Default rule: `EnvironmentType` ∈ {Production, Default} → protected;
  {Sandbox, Developer, Trial} → safe; anything else → unknown (yellow).
  `protectedUrls` wildcard patterns in `~/.paclife.json` override the type
  (covers real production mislabeled as Sandbox); `safeUrls` patterns mute it.
  The displayed warning states the *cause* in plain words, natural casing —
  `⚠ Production`, `⚠ Default Environment`, or `⚠ Protected` (URL rule) —
  never slogans or vocabulary the user has to learn first.
- **Statusline** — the pinned top row of the terminal, redrawn by the prompt hook.
- **Banner** — the on-demand detailed box rendered by `Show-PacLife -Full` (`alleyez`).
- **Identity** — who pac runs as: a *user* (UPN) or a *service principal*
  (AppId, client secret/cert auth). Service principals are visually unmistakable
  in the statusline so no one mistakes a CI/consultant identity for themselves.
- **Auth kind** — the profile's `Kind` (UNIVERSAL / DATAVERSE / ADMIN). Explains why
  some pac commands fail despite being "logged in". Shown in the statusline only when
  it is *not* UNIVERSAL (exception-based display: the modern default carries no
  information — same principle as Public cloud being dim while sovereign clouds are
  highlighted). Always visible in the full banner.
- **Theme matching** — PacLife may adopt the shades and segment shapes of the user's
  oh-my-posh theme so the statusline looks native next to their prompt. The semantic
  colors are inviolable: theme matching changes *nuances* (the theme's own red/green/
  yellow), never *meaning* (red = protected, green = safe, yellow = unknown/missing).
