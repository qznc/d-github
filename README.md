# GitHub v3 API for D

Library to communicate with GitHub via
[the official v3 REST API](https://developer.github.com/v3/).

Status: **Not really usable yet**

Expects an environment variable `GITHUB_OAUTH_TOKEN` for authentication.

```d
auto github = new Client("d-github-unittest");
auto user = github.getUser("dlang");
writeln(user.followers, " folks love ", user.name, "!");
auto repo = user.getRepo("phobos");
writeln(repo.description);
foreach(u; repo.contributors())
  writeln("contributor: ", u.login);
```

## Licence

This repository and all its content falls under Boost licence v1.0.
