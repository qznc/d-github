module github;

import std.stdio;
import std.json : parseJSON, JSONValue, JSON_TYPE;
import std.conv : text;
import std.array : empty;
import std.string : replace;
import std.process : environment;
import std.regex : ctRegex, matchFirst;
import std.algorithm : splitter, map;
import std.datetime : Clock, SysTime, dur;
import std.exception : assertThrown;

import requests : HTTPRequest;

enum ACCEPT_JSON = "application/vnd.github.v3+json";
enum GITHUB_ROOT = "https://api.github.com";

auto getResponse(string url) {
    auto token = environment["GITHUB_OAUTH_TOKEN"];
    auto rq = HTTPRequest();
    rq.verbosity = 2; // DEBUG
    rq.addHeaders(["Authorization": "token "~token,
        "Accept": ACCEPT_JSON]);
    return rq.get(url);
}

/* fetch JSON info on demand */
class LazyJSONObject {
    Client client;
    string url;
    JSONValue value;

    this (Client c, string url) {
        this.client = c;
        this.url = url;
    }

    this (Client c, JSONValue v) {
        this.client = c;
        this.value = v;
    }

    @property private JSONValue jsonObj() {
        if (value.isNull) {
            auto c = client.getContent(url);
            value = parseJSON(c);
        }
        return value;
    }

    @property private string getStr(string key)() {
        const v = jsonObj[key];
        if (v.type == JSON_TYPE.STRING)
            return v.str;
        else
            return null;
    }

    @property private size_t getInt(string key)() {
        const v = jsonObj[key];
        if (v.type == JSON_TYPE.INTEGER)
            return v.integer;
        else
            return 0;
    }

    @property private bool getBool(string key)() {
        const v = jsonObj[key];
        if (v.type == JSON_TYPE.TRUE)
            return true;
        else if (v.type == JSON_TYPE.FALSE)
            return false;
        else
            assert (0);
    }
}

struct urlCache {
    static immutable NO_GET_DURATION = dur!"seconds"(10);
    static immutable CACHE_MAX_SIZE = 16 * 1024 * 1024;

    this(string userAgent) {
        this.user_agent = userAgent;
    }

    struct entry {
        SysTime last_get;
        string url, etag, mdate, content;
        int opCmp(ref const entry e) const {
            if (e.last_get < this.last_get) return -1;
            if (e.last_get > this.last_get) return  1;
            if (e.content.length < this.content.length) return -1;
            if (e.content.length > this.content.length) return  1;
            if (e.url < this.url) return -1;
            if (e.url > this.url) return  1;
            return 0;
        }
    }
    entry[] cache;
    size_t[string] url_index;
    size_t total_cache_size;
    string user_agent = "D-Github";

    bool has(string url) {
        return null !is (url in url_index);
    }

    const(string) getContent(string url) {
        auto rq = HTTPRequest();
        rq.verbosity = 1; // DEBUG
        auto now = Clock.currTime();
        const cache_index = url in url_index;
        if (cache_index !is null) {
            /* we have something in cache */
            const e = cache[*cache_index];
            if ((now - e.last_get) < NO_GET_DURATION) {
                return e.content;
            }
            /* try to avoid data transfer via etag */
            if (e.etag)
                rq.addHeaders(["If-None-Match": e.etag]);
            if (e.mdate)
                rq.addHeaders(["If-Modified-Since": e.mdate]);
        }
        /* actual network access */
        auto token = environment["GITHUB_OAUTH_TOKEN"];
        rq.addHeaders(["Authorization": "token "~token,
                "User-Agent": user_agent,
                "Accept": ACCEPT_JSON]);
        auto res = rq.get(url);
        if (res.code == 304 && cache_index !is null) {
            /* content not modified, can serve from cache */
            return cache[*cache_index].content;
        }
        auto txt = text(res.responseBody);
        insertIntoCache(url, txt, now,
                res.responseHeaders.get("etag", ""),
                res.responseHeaders.get("Last-Modified", ""));
        return txt;
    }

    void insertIntoCache(const string url, const string data,
        const SysTime last_get = Clock.currTime(),
        const string etag = "", const string mdate = "")
    {
        if (total_cache_size > CACHE_MAX_SIZE) {
            /* Evict things from cache */
            size_t free_size = 0;
            const free_target = total_cache_size - (CACHE_MAX_SIZE * 2 / 3);
            foreach (i, e; cache) {
                free_size += e.content.length;
                url_index.remove(e.url);
                if (free_size > free_target) {
                    assert (free_size <= total_cache_size);
                    cache = cache[i..$];
                    break;
                }
            }
        }
        this.url_index[url] = cache.length;
        this.cache ~= entry(last_get, url, etag, mdate, data);
        this.total_cache_size += data.length;
    }
}

class Client {
    string[string] roots_;
    urlCache cache;

    this(string appname) {
        cache = urlCache(appname);
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

    string getContent(string url) {
        return cache.getContent(url);
    }

    void insertIntoCache(string url, string data,
        SysTime last_get = Clock.currTime(),
        string etag = "", string mdate = "")
    {
        cache.insertIntoCache(url, data, last_get, etag, mdate);
    }
}

class User : LazyJSONObject {
    const string name_;

    this(Client c, string name) {
        const url = c.getRootURL("user_url").replace("{user}", name);
        super(c, url);
        this.name_ = name;
    }

    @property public string login() { return name_; }
    @property public string avatar_url() { return getStr!"avatar_url"(); }
    @property public string html_url() { return getStr!"html_url"(); }
    @property public bool site_admin() { return getStr!"site_admin"() == "true"; }
    @property public string name() { return getStr!"name"(); }
    @property public string company() { return getStr!"company"(); }
    @property public string blog() { return getStr!"blog"(); }
    @property public string email() { return getStr!"email"(); }
    @property public string bio() { return getStr!"bio"(); }
    @property public long public_repos() { return getInt!"public_repos"; }
    @property public long public_gists() { return getInt!"public_gists"; }
    @property public long followers() { return getInt!"followers"; }
    @property public long following() { return getInt!"following"; }

    public Repo getRepo(string name) {
        return client.getRepo(name_, name);
    }
}

class Contributor : User {
    public const size_t contributionCount;
    this(Client c, JSONValue contributor) {
        super(c, contributor["login"].str);
        contributionCount = contributor["contributions"].integer;
    }
}

class Repo : LazyJSONObject {
    const string uname_;
    const string rname_;

    this(Client c, string user, string repo) {
        assert (!user.empty);
        assert (!repo.empty);
        auto url = c.getRootURL("repository_url")
            .replace("{owner}", user)
            .replace("{repo}", repo);
        super(c, url);
        this.uname_ = user;
        this.rname_ = repo;
    }

    @property public string name() { return getStr!"name"(); }
    @property public string full_name() { return getStr!"full_name"(); }
    @property public string description() { return getStr!"description"(); }
    @property public string ssh_url() { return getStr!"ssh_url"(); }
    @property public string language() { return getStr!"language"(); }
    @property public string default_branch() { return getStr!"default_branch"(); }
    @property public string svn_url() { return getStr!"svn_url"(); }
    @property public string html_url() { return getStr!"html_url"(); }

    @property public auto pullRequests() {
        auto url = getStr!"pulls_url".replace("{/number}", "");
        return paginated!PullRequest(client, url);
    }

    @property public auto contributors() {
        auto url = getStr!"contributors_url"();
        return paginated!Contributor(client, url);
    }

    @property public auto collaborators() {
        auto url = getStr!"collaborators_url"();
        auto c = client.getContent(url);
        auto j = parseJSON(c);
    }
}

class PullRequest : LazyJSONObject {
    const size_t id;

    this(Client c, JSONValue o) {
        this(c, o["_links"]["self"]["href"].str);
    }

    this(Client c, string url) {
        super(c, url);
        this.id = id;
    }

    @property public string state() { return getStr!"state"(); }
    @property public string title() { return getStr!"title"(); }
    @property public string body_() { return getStr!"body"(); }
    @property public string createdAt() { return getStr!"created_at"(); }
    @property public string updatedAt() { return getStr!"updated_at"(); }
    @property public string closedAt() { return getStr!"closed_at"(); }
    @property public string mergedAt() { return getStr!"merged_at"(); }
    @property public bool locked() { return getBool!"locked"(); }
    @property public bool merged() { return getBool!"merged"(); }
    @property public bool mergeable() { return getBool!"mergeable"(); }
    @property public size_t commentCount() { return getInt!"comments"(); }
    @property public size_t commits() { return getInt!"commits"(); }
    @property public size_t additions() { return getInt!"additions"(); }
    @property public size_t deletions() { return getInt!"deletions"(); }
    @property public size_t changedFiles() { return getInt!"changed_files"(); }

    @property public auto comments() {
        auto url = getStr!"comments_url"();
        auto c = client.getContent(url);
        auto j = parseJSON(c);
        return map!((JSONValue v)=>new Comment(client,v))(j.array);
    }
}

class Comment {
    JSONValue data;
    this(Client c, JSONValue o) {
        this.data = o;
    }

    @property public string body_() { return data["body"].str; }
    @property public string createdAt() { return data["created_at"].str; }
    @property public string updatedAt() { return data["updated_at"].str; }
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
    foreach (pr; repo.pullRequests()) {
        writeln("PR: ", pr.title, " with ", pr.commits, " commits");
        foreach (c; pr.comments) {
            writeln("Comment: ", c.body_);
            break;
        }
        break;
    }
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
