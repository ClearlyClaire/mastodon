#  Guidelines for Working with Git(Lab)  #

Kibicat Mastodon aspires maintain a mature, sophisticated, and
  hassle·free development environment for its contributors, and much of
  that comes down to how we interface with our version control system
  (Git) and development platform (GitLab).
This document provides an outline of current bestpractices followed by
  the Kibicat team in this area.

It is okay if you are not deeply familiar with these technologies as a
  new contributor, but you should commit to *becoming* familiar over
  the course of your work.
Understanding good Git practices is as important to Kibicat Mastodon
  development as understanding other core technologies like JavaScript
  or Ruby.

##  Git Model  ##

Kibicat Mastodon uses a trunk‐based development model, where small,
  incremental commits are added to a main branch (called trunk 🐘),
  which is kept in an operational state thanks to continuous
  integration.
Large or long‐living feature branches are discouraged.

Kibicat Mastodon strives to maintain a linear history with no merge
  commits.
(Note that upstream does not follow this model, and you should not
  depend on it.)
Merge requests must be rebased on trunk before they can be merged, and
  the merge will simply fastforward to the final commit in the merge
  request branch.

Try not to rebase a branch if you know another branch is about to get
  merged—you will just have to rebase it again.

##  Branch Etiquette  ##

GitLab takes no issue with force‐pushing to open merge requests—please
  do.
Your goal should be to arrange your merge request in a way which is
  easiest for review: by grouping together similar changes, and by
  squashing any fix·ups.
If you’re going to be force‐pushing anyway, it’s a good idea to fetch
  and rebase on top of trunk while you’re at it.

A branch with a large number of commits can be squashed on merging.
Squashing should be performed for commits which are separated for ease
  of review, but which don’t really make sense on their own (because
  they provide an incomplete implementation).
In other situations, leaving commits separate is probably preferred.

##  Commits  ##

Following typical Git conventions, commits should encapsulate a single
  conceptual “change” and be described with an informative commit
  message.
Commit messages should consist of a summary (at most 50 characters) and
  an extended description (hardwrapped to no more than 72 columns),
  separated by a single blank line.
Summaries should be conjugated in the infinitive, begin with a capital
  letter, and not end in a period.
The formatting of extended descriptions is left to the discretion of
  the commit author.

Please do not skip the extended description unless your work really is
  trivial or obvious.
If you had to explore multiple routes when working on a commit,
  document each and explain why you chose the route you did.

If you need to reference a specific issue on GitLab in your commit
  message, please do so via the full U·R·L.
Because Kibicat Mastodon is a fork, it is generally not obvious whether
  issue numbers refer to local issues or upstream ones.
In most cases, referencing an issue in a commit message is unnecessary;
  just remember to do so when you open a merge request.

##  Issues &amp; Merge Requests  ##

Issues should be created with a small scope and defined acceptance
  criteria (so it is clear when the issue can be closed).
Issues of grand scope should be labelled ~status::EPIC and smaller
  issues should be defined.

The ~status::Ready, ~"status::In Progress", and ~status::Review labels
  should be used to track which issues are being worked on.
If you are working on an issue, please assign it to yourself so that
  others don’t try to pick it up.
[The development board][BOARD] provided by GitLab can aid in keeping
  track of the status of current work.

[BOARD]: <https://gitlab.com/kibicat/mastodon/-/boards>

With the exception of epics, issues and merge requests should be
  restricted to a single conceptual “area” :— Meta, Backend, Ontology,
  Serialization, Networking, Frontend.
There is a scoped label for each of these which you should use.
If your work touches multiple areas, it should be broken up into
  multiple issues ∣ merge requests.
For example, one might need to implement something in the database
  (~area::Backend), then in the API (~area::Serialization), then in the
  web application (~area::Frontend).
This should be three separate issues (linked by an epic) and ultimately
  three merge requests.
