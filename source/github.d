module github;

import std.stdio;

class Client {
    string appname;

    this(string appname) {
        this.appname = appname;
    }

    public auto getUser(string name) {
        return new User();
    }
}

class User {
    this() { }

    @property public auto followers() { return 42; }
}

unittest {
    auto github = new Client("MyAmazingApp");
    auto user = github.getUser("half-ogre");
    writeln(user.followers, " folks love the half ogre!");
}
