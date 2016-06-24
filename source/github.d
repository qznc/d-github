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
}

unittest {
    auto github = new Client("d-github-unittest");
    auto user = github.getUser("qznc");
    writeln(user.followers, " folks love ", user.name, "!");
}
