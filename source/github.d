module github;

import std.stdio;
import std.json : parseJSON, JSONValue, JSON_TYPE;
import std.conv : text;
import std.array : empty;
import std.string : replace;

import requests : getContent;

enum ACCEPT_JSON = "application/vnd.github.v3+json";
enum GITHUB_ROOT = "https://api.github.com";

class Client {
    string appname;
    string[string] roots_;

    this(string appname) {
        this.appname = appname;
    }

    public auto getUser(string name) {
        return new User(this, name);
    }

    public auto getRepo(string user, string repo) {
        return new Repo(this, user, repo);
    }

    public auto getRootURL(string key) {
        return roots[key];
    }

    @property public const(string[string]) roots() {
        if (roots_ == null) {
            auto c = getContent(GITHUB_ROOT);
            auto j = parseJSON(c);
            foreach(string k, v; j)
                roots_[k] = v.str;
        }
        return roots_;
    }
}

class User {
    Client client_;
    const string name_;
    JSONValue uinfo_ = JSONValue(null);

    this(Client c, string name) {
        this.client_ = c;
        this.name_ = name;
    }

    @property private auto uinfo() {
        if (uinfo_.isNull) {
            string url = client_.getRootURL("user_url");
            url = url.replace("{user}", name_);
            auto c = getContent(url);
            uinfo_ = parseJSON(c);
        }
        return uinfo_;
    }

    @property private string uinfoStr(string key)() {
        auto v = uinfo[key];
        if (v.type == JSON_TYPE.STRING)
            return v.str;
        else
            return null;
    }

    @property public string login() { return uinfoStr!"login"(); }
    @property public string avatar_url() { return uinfoStr!"avatar_url"(); }
    @property public string html_url() { return uinfoStr!"html_url"(); }
    @property public bool site_admin() { return uinfoStr!"site_admin"() == "true"; }
    @property public string name() { return uinfoStr!"name"(); }
    @property public string company() { return uinfoStr!"company"(); }
    @property public string blog() { return uinfoStr!"blog"(); }
    @property public string email() { return uinfoStr!"email"(); }
    @property public string bio() { return uinfoStr!"bio"(); }
    @property public long public_repos() { return uinfo["public_repos"].integer; }
    @property public long public_gists() { return uinfo["public_gists"].integer; }
    @property public long followers() { return uinfo["followers"].integer; }
    @property public long following() { return uinfo["following"].integer; }

    public Repo getRepo(string name) {
        return client_.getRepo(name_, name);
    }
}

class Repo {
    Client client_;
    const string uname_;
    const string rname_;
    JSONValue rinfo_ = JSONValue(null);

    this(Client c, string uname, string rname) {
        this.client_ = c;
        this.uname_ = uname;
        this.rname_ = rname;
    }

    @property private auto rinfo() {
        if (rinfo_.isNull) {
            string url = client_.getRootURL("repository_url");
            url = url.replace("{owner}", uname_).replace("{repo}", rname_);
            auto c = getContent(url);
            rinfo_ = parseJSON(c);
        }
        return rinfo_;
    }

    @property private string rinfoStr(string key)() {
        auto v = rinfo[key];
        if (v.type == JSON_TYPE.STRING)
            return v.str;
        else
            return null;
    }

    @property public string name() { return rinfoStr!"name"(); }
    @property public string full_name() { return rinfoStr!"full_name"(); }
    @property public string description() { return rinfoStr!"description"(); }
    @property public string ssh_url() { return rinfoStr!"ssh_url"(); }
    @property public string language() { return rinfoStr!"language"(); }
    @property public string default_branch() { return rinfoStr!"default_branch"(); }
    @property public string svn_url() { return rinfoStr!"svn_url"(); }
    @property public string html_url() { return rinfoStr!"html_url"(); }

    @property public auto pullRequests() {
        auto url = rinfoStr!"pulls_url".replace("{/number}", "");
        auto c = getContent(url);
        auto j = parseJSON(c);
        foreach (v; j.array) writeln("PR: ", v["title"].str);
    }
}

unittest {
    auto github = new Client("d-github-unittest");
    //foreach(k,v; github.roots) writeln(k, ": ", v);
    auto user = github.getUser("dlang");
    writeln(user.followers, " folks love ", user.name, "!");
    auto repo = user.getRepo("phobos");
    //foreach (string k,v; repo.rinfo) writeln(k, ": ", v);
    writeln(repo.description);
    repo.pullRequests();
}
