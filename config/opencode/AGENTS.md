# Global agent rules

## Communication

- Be concise. No greetings, filler, or repeated summaries.
- Say what changed and how it was verified. If something is unknown, say so.
- After a tricky fix, add one or two sentences explaining why it works.

## Work

- State the plan and the verification before editing.
- Run the smallest meaningful check after changes. Never claim a command passed without running it.
- Reuse earlier command output. Do not rerun a command unless its inputs changed.
- Read the file, run the command, or say it is unknown. Never invent paths, APIs, hashes, or results.
- Touch only what the task requires. Do not refactor unrelated code.
- Ask before destructive actions, credential changes, or anything that cannot be undone.

## Scanning limits

- Never scan, index, or search `Siemens`, `MATLAB`, `datasets`, or `.venv` directories.
- Do not run recursive searches from a drive root or a home directory. Start from the project folder.
- Prefer `rg` with an explicit path and `--glob` filters over broad file walks.

## Secrets

- Never print tokens, API keys, passwords, SSH keys, or `.env` contents.
- Read secrets from environment variables. Do not write them into repositories or configs.
- Do not read `~/.ssh` or KeePass databases.

## Platform

- Windows 11, PowerShell 7. Scripts must also run on Windows PowerShell 5.1.
- Engineering apps use their native light theme. Editors and terminals use Graphite Amber.
