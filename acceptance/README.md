# Running Acceptance Tests

This acceptance suite allows you to test bolt using the following methods:

    * gem: Install bolt via gem from a gemsource defined as an environment
      variable (defaults to https://gems.rubygems.org).
    * TODO: git: Install bolt via the git repo from a SHA defined as an
      environment variable (defaults to #master/HEAD).

The tests assume the following Beaker roles be assigned to your SUT nodes:
    * `bolt`: This role defines the node that will act as the `bolt`
      controller node. There should be only one `bolt` node defined in a
      given Beaker hosts file.
    * `ssh`: Nodes defined with this role will be used to test bolt's SSH
      connection protocal. Any number of nodes can be defined with this role.
    * `winrm`: Nodes defined with this role will be used to test bolt's WinRM
      connection protocal. Any number of nodes can be defined with this role.

TODO: Create Rakefile with defined rake tasks for the above.

## Setup

Prior to running the test commands, you must install the dependencies. This is
accomplished by running `bundle install` from within the `acceptance`
directory of your `bolt` git clone.

## Running Tests on the vcloud

### Gem

1. Create Beaker hosts file.
You should run `beaker-hostgenerator` to create the hosts.yaml file used by
beaker to run the tests. The examples below illustrate common platforms to
test against.
_Centos 7_
```
 bundle exec beaker-hostgenerator centos7-64bolt,ssh.-centos7-64ssh. > hosts.yaml
```
_Ubuntu 16.04_
```
 bundle exec beaker-hostgenerator ubuntu1604-64bolt,ssh.-ubuntu1604-64ssh. > hosts.yaml
```
_Windows 10 Enterprise_
```
 bundle exec beaker-hostgenerator windows10ent-64bolt,ssh.-windows10ent-64ssh. > hosts.yaml
```
_OS X 10.12_
```
  bundle exec beaker-hostgenerator osx1012-64bolt,ssh.-osx1012-64ssh. > hosts.yaml
```
1. Run test suite with beaker
```
  bundle exec beaker               \
      -o config/gem/options.rb     \
      -h hosts.yaml                \
      -t tests
```
