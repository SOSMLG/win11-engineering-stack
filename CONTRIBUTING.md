# contributing

small project, simple rules. `AGENTS.md` has the full list of lessons. the short version:

1. try it in a VM first. this changes system settings.
2. run `.\Validate.ps1 -Profile daily` and `.\Install.ps1 -Profile iot -DryRun` before a real run. read the log before committing.
3. new switches default off. every write gets a dry-run log line.
4. check `$LASTEXITCODE` after native exes. try/catch alone lies.
5. fresh-install-only deploys never overwrite a lived-in config.
6. no secrets in the tree. blank values only.
7. keep comments short and plain, like the rest of the repo.

bugs and ideas go in issues. for anything security related, read `SECURITY.md` first.

local workflow: [english guide](https://github.com/SOSMLG/.github/blob/main/docs/GIT_GUIDE.md) / [arabic guide](https://github.com/SOSMLG/.github/blob/main/docs/GIT_GUIDE.ar.md).
