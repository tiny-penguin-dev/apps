#!/usr/bin/env python3
"""Get Sentry ready for an app before a TestFlight build.

Finds the app's Sentry project, creating it if it doesn't exist yet, and looks
up its DSN so the build can bake it in. Nothing about Sentry has to be set up
by hand for a new app: one auth token is enough.

Writes SENTRY_DSN and SENTRY_ORG to $GITHUB_ENV (when set) and prints the DSN
otherwise. If SENTRY_DSN is already set, it's kept as an override.

Usage: sentry-prepare-app.py <project-slug> [display-name]
Env:   SENTRY_AUTH_TOKEN  a Sentry token with org:read, team:read, project:read,
                          project:write and project:releases
                          (project:admin is not needed). An organization token
                          (sntrys_...) can't create projects; use a personal or
                          internal integration token.
       SENTRY_ORG         organization slug (optional if the token sees one org)
       SENTRY_TEAM        team that owns new projects (optional: the first team)
       SENTRY_URL         default https://sentry.io
"""

import json
import os
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("SENTRY_URL", "https://sentry.io").rstrip("/") + "/api/0"
TOKEN = os.environ.get("SENTRY_AUTH_TOKEN", "")


class SentryError(Exception):
    pass


def call(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method, headers={
        "Authorization": f"Bearer {TOKEN}",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            text = resp.read().decode()
            return json.loads(text) if text else None
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        detail = e.read().decode()[:300]
        hint = ""
        if e.code in (401, 403):
            hint = (" The token needs org:read, team:read, project:read, project:write and project:releases. An organization"
                    " token (sntrys_...) can't create projects.")
        raise SentryError(f"{method} {path} failed with {e.code}: {detail}.{hint}") from None
    except OSError as e:
        raise SentryError(f"Couldn't reach Sentry ({method} {path}): {e}") from None


def find_org():
    org = os.environ.get("SENTRY_ORG", "")
    if org:
        return org
    orgs = call("GET", "/organizations/?member=1") or []
    if len(orgs) != 1:
        names = ", ".join(o["slug"] for o in orgs) or "none"
        raise SentryError(f"Set the SENTRY_ORG variable: the token sees {len(orgs)} organizations ({names}).")
    return orgs[0]["slug"]


def ensure_project(org, slug, name):
    project = call("GET", f"/projects/{org}/{slug}/")
    if project:
        print(f"Sentry project {org}/{slug} exists.")
        return
    team = os.environ.get("SENTRY_TEAM", "")
    if not team:
        teams = call("GET", f"/organizations/{org}/teams/") or []
        if not teams:
            raise SentryError(f"Organization {org} has no teams to own a new project.")
        team = teams[0]["slug"]
    call("POST", f"/teams/{org}/{team}/projects/", {
        "name": name,
        "slug": slug,
        "platform": "apple-ios",
        "default_rules": True,
    })
    print(f"Created Sentry project {org}/{slug} (team {team}).")


def find_dsn(org, slug):
    keys = call("GET", f"/projects/{org}/{slug}/keys/") or []
    active = [k for k in keys if k.get("isActive", True)]
    if not active:
        active = [call("POST", f"/projects/{org}/{slug}/keys/", {"name": "Default"})]
    return active[0]["dsn"]["public"]


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    slug = sys.argv[1]
    name = sys.argv[2] if len(sys.argv) > 2 else slug
    if not TOKEN:
        sys.exit("SENTRY_AUTH_TOKEN is not set.")

    org = find_org()
    ensure_project(org, slug, name)
    dsn = os.environ.get("SENTRY_DSN") or find_dsn(org, slug)

    env_file = os.environ.get("GITHUB_ENV")
    if env_file:
        print(f"::add-mask::{dsn}")
        with open(env_file, "a") as f:
            f.write(f"SENTRY_DSN={dsn}\nSENTRY_ORG={org}\n")
        print("Sentry DSN is set for this build.")
    else:
        print(dsn)


if __name__ == "__main__":
    try:
        main()
    except SentryError as e:
        print(f"::warning::{e}")
        sys.exit(1)
