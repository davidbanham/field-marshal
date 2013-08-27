# Field Marshal

Field-Marshal is an open source, simple, private PaaS you can run yourself.

Field Marshal is designed to work with [Cavalry](https://github.com/davidbanham/cavalry) and is a rewrite of [Rear Admiral](https://github.com/PinionTech/rear-admiral).

1. You run one or more Cavalry slaves on different servers.
2. You git push your code to Field-Marshal.
3. You tell Field-Marshal how many of each of your services you want to run, how they should be started, and where people look for them.

Field-Marshal takes care of the rest, routing the http traffic, respawning instances if they die, re-allocating the jobs if a slave goes down.

[![Build Status](https://travis-ci.org/davidbanham/field-marshal.png?branch=master)](https://travis-ci.org/davidbanham/field-marshal)

#Installation

npm:

    npm install -g field-marshal

git:

    git clone https://github.com/davidbanham/field-marshal
    npm install

Port 4000 and 4001 will need to be accessible by the slaves to check in and fetch code.

If you install globally, field-marshal will look for manifests and store repositories in the directory it's run from.

#Running it

Configuration paramaters are passed in via environment variables. eg:

CAVALRYPASS=cavalrypassword HOSTNAME=localhost SECRET=password node index.js

If they're not present, a default will be substituted.
- CAVALRYPASS is the password that field-marshal will use to authenticate itself to the cavalry slaves.
- HOSTNAME is the fqdn or IP that the cavalry slaves can use to reach field-marshal.
- SECRET is the password the cavalry slaves will use to authenticate with field-marshal.

The manifest is one or more JSON files in the manifest directory. An example is:

```json
    {
      "beep": {
        "instances": "*",
        "load": 1,
        "routing": {
          "domain": "beep.example.com"
        },
        "opts": {
          "setup": [
            "npm",
            "install"
          ],
          "command": [
            "node",
            "server.js"
          ],
          "commit": "8b7243393950e0209c7a9346e9a1a839b99619d9",
          "env": {
            "PORT": "RANDOM_PORT"
          }
        }
      }
    }
```

Variables of note are:
- instances: How many instances of the thing you want to be running at once. Substituting the character '*' means the thing will run on all available slaves, regardless of how many there are.
- load: How 'heavy' the process is relative to your other processes. This is used when calculating which slave to designate a task to. So, a process with a load of 0.5 will be half as 'heavy' as something with a load of 1.0
- routing: These are passed through to the nginx routing layer.
  - domain: The fqdn that requests to this process will be directed at. Allows nginx to proxy the request to the right place.
  - method: The method nginx should use to allocate requests to upstream servers. Defaults to least_conn. Info here: http://wiki.nginx.org/HttpUpstreamModule#Directives
- env: Any environment variables you want to be in place when Cavalry executes the process
  - PORT: Port is required for the nginx routing layer to know where to send requests. Substituting the string 'RANDOM_PORT' will choose a free port on the system between 8000 and 9000.

#Getting your code into it

Field-marshal starts a git server on port 4001. Just push to it!

    git push http://git:testingpass@localhost:4001/beep master

Authenticate with whatever you set in the SECRET environment variable. Here we've called the repo 'beep'. Each repo needs to have a unique name so you can refer to it later.
