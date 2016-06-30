module github;

import std.stdio;
import std.json : parseJSON, JSONValue, JSON_TYPE;
import std.conv : text;
import std.array : empty;
import std.string : replace;
import std.process : environment;
import std.regex : ctRegex, matchFirst;
import std.algorithm : splitter;
import std.datetime : Clock, SysTime, dur;
import std.exception : assertThrown;

import requests : HTTPRequest;

enum ACCEPT_JSON = "application/vnd.github.v3+json";
enum GITHUB_ROOT = "https://api.github.com";

auto getResponse(string url) {
    auto token = environment["GITHUB_OAUTH_TOKEN"];
    auto rq = HTTPRequest();
    rq.verbosity = 2;
    rq.addHeaders(["Authorization": "token "~token,
        "Accept": ACCEPT_JSON]);
    return rq.get(url);
}

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
            auto c = this.getContent(GITHUB_ROOT);
            auto j = parseJSON(c);
            foreach(string k, v; j)
                roots_[k] = v.str;
        }
        return roots_;
    }

    /* To reduce traffic, we need some CACHING */
    immutable NO_GET_DURATION = dur!"seconds"(10);
    struct url_metainfo {
        size_t content_size;
        SysTime last_get;
        string etag, mdate;
    }
    url_metainfo[string] cacheinfo;
    string[string] cache;
    size_t cache_size;

    string getContent(string url) {
        auto rq = HTTPRequest();
        rq.verbosity = 2; // DEBUG
        auto now = Clock.currTime();
        if (url in cacheinfo) {
            /* we have something in cache */
            auto meta = cacheinfo[url];
            if ((now - meta.last_get) < NO_GET_DURATION) {
                return cache[url];
            }
            /* try to avoid data transfer via etag */
            if (meta.etag)
                rq.addHeaders(["If-None-Match": meta.etag]);
            if (meta.mdate)
                rq.addHeaders(["If-Modified-Since": meta.mdate]);
        }
        /* actual network access */
        auto token = environment["GITHUB_OAUTH_TOKEN"];
        rq.addHeaders(["Authorization": "token "~token,
                "User-Agent": appname,
                "Accept": ACCEPT_JSON]);
        auto res = rq.get(url);
        auto txt = text(res.responseBody);
        insertIntoCache(url, txt, now,
            res.responseHeaders.get("etag", ""),
            res.responseHeaders.get("Last-Modified", ""));
        return txt;
    }

    void insertIntoCache(string url, string data,
        SysTime last_get = Clock.currTime(),
        string etag = "", string mdate = "")
    {
        cacheinfo[url] = url_metainfo(data.length, last_get, etag, mdate);
        cache[url] = data;
        cache_size += data.length;
        // TODO Evict things from cache! This is a memory leak.
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
            auto c = client_.getContent(url);
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

    @property public string login() { return name_; }
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

class Contributor : User {
    public const size_t contributionCount;
    this(Client c, JSONValue contributor) {
        super(c, contributor["login"].str);
        contributionCount = contributor["contributions"].integer;
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
            auto c = client_.getContent(url);
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
        auto c = client_.getContent(url);
        auto j = parseJSON(c);
        foreach (v; j.array) writeln("PR: ", v["title"].str);
    }

    @property public auto contributors() {
        auto url = rinfoStr!"contributors_url"();
        return paginated!Contributor(client_, url);
    }

    @property public auto collaborators() {
        auto url = rinfoStr!"collaborators_url"();
        auto c = client_.getContent(url);
        auto j = parseJSON(c);
    }
}

struct paginated(T) {
    immutable int default_items_per_page = 30;
    size_t items_on_page = default_items_per_page;
    size_t i = 0;
    Client client_;
    string next_url;
    JSONValue current;

    this (Client c, string url) {
        this.client_ = c;
        this.next_url = url;
        updateCurrent();
    }

    @property auto front() {
        return new T(client_, current[i]);
    }

    void popFront() {
        if (i+1 < items_on_page) {
            i += 1;
        } else {
            i = 0;
            updateCurrent();
        }
    }

    @property bool empty() { return current.isNull; }

    private void updateCurrent() {
        if (next_url == null) {
            current = null;
            return;
        }
        auto r = getResponse(next_url);
        auto link = r.responseHeaders["link"];
        next_url = null; /* stays null if last page */
        foreach (l; link.splitter(',')) {
            auto ctr = ctRegex!("<([^>]*)>; rel=\"([^\"]*)\"");
            auto m = matchFirst(l, ctr);
            auto url = m[1];
            auto rel = m[2];
            if (rel == "next")
                next_url = url;
        }
        current = parseJSON(r.responseBody);
        assert (current.array.length <= items_on_page);
        items_on_page = current.array.length;
    }
}

unittest {
    auto github = new Client("https://github.com/qznc/d-github");
    //foreach(k,v; github.roots) writeln(k, ": ", v);
    auto user = github.getUser("dlang");
    writeln(user.followers, " folks love ", user.name, "!");
    auto repo = user.getRepo("phobos");
    //foreach (string k,v; repo.rinfo) writeln(k, ": ", v);
    writeln(repo.description);
    repo.pullRequests();
    size_t n = 0;
    foreach(u; repo.contributors()) {
        if (n > 40) break;
        n += 1;
        writeln("contributor ", u.login, " has ", u.contributionCount, " commits");
    }
    auto u2 = github.getUser("dlang");
    writeln(u2.name);
}

unittest {
    auto github = new Client("https://github.com/qznc/d-github");
    github.insertIntoCache(GITHUB_ROOT, `{
            "current_user_url": "https://api.github.com/user",
            "rate_limit_url": "https://api.github.com/rate_limit",
            "repository_url": "https://api.github.com/repos/{owner}/{repo}",
            "fake_entry": "HAHAHA"
    }`, Clock.currTime()); // cache prevents network access ;)
    /* normal usage would be */
    assert (github.getRootURL("current_user_url") == "https://api.github.com/user");
    /* check we actually got the entry from cache */
    assert (github.getRootURL("fake_entry") == "HAHAHA");
    /* the cache entry has no url for user info */
    import core.exception : RangeError;
    assertThrown!RangeError(github.getUser("dlang").name);
}
