#!/usr/bin/env python3
"""Offline tests for ontology/scripts/ontology.py.

Each test builds a throwaway git repo under a temp dir and drives the CLI as a
subprocess, the way the skill does. No network; nothing outside the temp dir.

    python3 ontology/tests/test_ontology.py
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "ontology.py"
GIT_ENV = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.invalid",
           "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.invalid"}


class Repo:
    def __init__(self, use_git=True):
        self.root = Path(tempfile.mkdtemp(prefix="ontology-test-"))
        self.write("src/api/routes.py", "def routes(): pass\n")
        self.write("src/billing/charge.py", "def charge(): pass\n")
        if use_git:
            self.git("init", "-q")
            self.commit("init")

    def write(self, rel, text):
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)

    def git(self, *args):
        subprocess.run(["git", *args], cwd=self.root, check=True, capture_output=True,
                       env={**os.environ, **GIT_ENV})

    def commit(self, msg):
        self.git("add", "-A", "--", "src")
        self.git("commit", "-qm", msg)

    def run(self, *args, stdin=None):
        env = {k: v for k, v in os.environ.items() if k != "ONTOLOGY_DIR"}
        return subprocess.run([sys.executable, str(SCRIPT), *args], cwd=self.root, input=stdin,
                              capture_output=True, text=True, env=env)

    def ok(self, *args, stdin=None):
        r = self.run(*args, stdin=stdin)
        assert r.returncode == 0, f"{args} exited {r.returncode}: {r.stderr}"
        return json.loads(r.stdout) if r.stdout.lstrip().startswith(("{", "[")) else r.stdout

    def fails(self, *args, code=1, stdin=None):
        r = self.run(*args, stdin=stdin)
        assert r.returncode == code, f"{args} exited {r.returncode}, wanted {code}: {r.stdout}{r.stderr}"
        return r.stderr

    def cleanup(self):
        shutil.rmtree(self.root, ignore_errors=True)


def seed(repo):
    repo.ok("init")
    repo.ok("add", "--type", "Area", "--props",
            '{"name":"Checkout","responsibility":"Turns a cart into a paid order"}', "--source", "src/api")
    repo.ok("add", "--type", "Capability", "--props",
            '{"name":"Place order","summary":"A customer buys what is in their cart"}',
            "--source", "src/api/routes.py:1")
    repo.ok("add", "--type", "Concept", "--props", '{"name":"Order","definition":"A customer request to buy"}')
    repo.ok("link", "--from", "cap:place-order", "--rel", "part_of", "--to", "area:checkout")
    repo.ok("link", "--from", "cap:place-order", "--rel", "changes", "--to", "term:order")


class Base(unittest.TestCase):
    use_git = True

    def setUp(self):
        self.repo = Repo(self.use_git)

    def tearDown(self):
        self.repo.cleanup()


class InitTests(Base):
    def test_missing_store_is_usage_error(self):
        self.assertIn("setup wizard", self.repo.fails("summary", code=2))
        self.assertFalse(self.repo.ok("status")["exists"])

    def test_local_by_default_ignores_whole_dir(self):
        self.repo.ok("init")
        self.assertEqual((self.repo.root / ".ontology/.gitignore").read_text().splitlines()[-1], "*")
        self.assertFalse(self.repo.ok("status")["shared"])

    def test_shared_keeps_graph_committable(self):
        self.repo.ok("init", "--shared")
        self.assertTrue(self.repo.ok("status")["shared"])

    def test_reinit_needs_force_and_keeps_backup(self):
        self.repo.ok("init")
        self.repo.fails("init", "--template", "empty", code=2)
        out = self.repo.ok("init", "--template", "empty", "--force")
        self.assertTrue(Path(out["schema_backup"]).exists())
        self.assertEqual(self.repo.ok("status")["types"], [])

    def test_unknown_template(self):
        self.assertIn("application", self.repo.fails("init", "--template", "nope", code=2))


class WriteValidationTests(Base):
    def setUp(self):
        super().setUp()
        seed(self.repo)

    def test_readable_ids(self):
        ids = [e["id"] for e in self.repo.ok("find")]
        self.assertEqual(ids, ["area:checkout", "cap:place-order", "term:order"])

    def test_id_collision_rejected(self):
        self.assertIn("already exists", self.repo.fails(
            "add", "--type", "Area", "--props", '{"name":"checkout","responsibility":"x"}'))

    def test_unknown_type(self):
        self.assertIn("unknown type", self.repo.fails("add", "--type", "Widget", "--props", '{"name":"w"}'))

    def test_required_property(self):
        self.assertIn("missing required property 'responsibility'",
                      self.repo.fails("add", "--type", "Area", "--props", '{"name":"x"}'))

    def test_enum(self):
        self.assertIn("must be one of", self.repo.fails(
            "add", "--type", "Actor", "--props", '{"name":"x","kind":"spaceship"}'))

    def test_property_type(self):
        self.assertIn("must be a array", self.repo.fails(
            "add", "--type", "Concept", "--props", '{"name":"x","definition":"d","aliases":"y"}'))

    def test_secrets_forbidden(self):
        self.assertIn("forbidden", self.repo.fails(
            "add", "--type", "Actor", "--props", '{"name":"Payment provider","kind":"system","api_key":"x"}'))

    def test_implementation_detail_rejected(self):
        err = self.repo.fails("add", "--type", "Area", "--props",
                              '{"name":"Search","responsibility":"Find products","framework":"django"}')
        self.assertIn("'framework' is not defined for Area", err)
        self.assertIn("sources", err)

    def test_update_cannot_drop_required(self):
        self.assertIn("missing required", self.repo.fails("update", "--id", "area:checkout", "--unset", "responsibility"))

    def test_link_to_missing_entity(self):
        self.assertIn("does not exist", self.repo.fails(
            "link", "--from", "cap:place-order", "--rel", "part_of", "--to", "area:ghost"))

    def test_link_endpoint_types(self):
        self.assertIn("cannot end at a Concept", self.repo.fails(
            "link", "--from", "area:checkout", "--rel", "part_of", "--to", "term:order"))

    def test_unknown_relation(self):
        self.assertIn("unknown relation", self.repo.fails(
            "link", "--from", "area:checkout", "--rel", "loves", "--to", "term:order"))

    def test_cardinality_one_parent(self):
        self.repo.ok("add", "--type", "Area", "--props", '{"name":"Payments","responsibility":"Take money"}')
        self.assertIn("many_to_one allows one", self.repo.fails(
            "link", "--from", "cap:place-order", "--rel", "part_of", "--to", "area:payments"))

    def test_acyclic(self):
        self.repo.ok("add", "--type", "Area", "--props", '{"name":"Storefront","responsibility":"Selling"}')
        self.repo.ok("link", "--from", "area:checkout", "--rel", "part_of", "--to", "area:storefront")
        self.assertIn("cycle", self.repo.fails(
            "link", "--from", "area:storefront", "--rel", "part_of", "--to", "area:checkout"))
        self.repo.ok("add", "--type", "Decision", "--props", '{"title":"A","status":"accepted"}')
        self.repo.ok("add", "--type", "Decision", "--props", '{"title":"B","status":"accepted"}')
        self.repo.ok("link", "--from", "dec:b", "--rel", "supersedes", "--to", "dec:a")
        self.assertIn("cycle", self.repo.fails("link", "--from", "dec:a", "--rel", "supersedes", "--to", "dec:b"))

    def test_duplicate_link_is_noop(self):
        out = self.repo.ok("link", "--from", "cap:place-order", "--rel", "changes", "--to", "term:order")
        self.assertEqual(out["written"], 0)
        self.assertEqual(len(self.repo.ok("get", "--id", "cap:place-order")["out"]), 2)

    def test_remove_cascades_relations(self):
        out = self.repo.ok("remove", "--id", "cap:place-order")
        self.assertEqual(out["results"][0]["edges_removed"], 2)
        self.assertEqual(self.repo.ok("get", "--id", "area:checkout")["in"], [])
        self.assertTrue(self.repo.ok("validate")["valid"])


class BatchTests(Base):
    def test_batch_is_atomic(self):
        self.repo.ok("init")
        batch = "\n".join(json.dumps(o) for o in [
            {"op": "add", "type": "Area", "props": {"name": "Checkout", "responsibility": "Sell"}},
            {"op": "add", "type": "Capability", "props": {"name": "Place order", "summary": "Buy"}},
            {"op": "link", "from": "cap:place-order", "rel": "part_of", "to": "area:checkout"},
            {"op": "link", "from": "cap:place-order", "rel": "changes", "to": "term:ghost"},
        ])
        err = self.repo.fails("apply", "--file", "-", stdin=batch)
        self.assertIn("op 4", err)
        self.assertIn("nothing written", err)
        self.assertEqual(self.repo.ok("status")["entities"], 0)
        good = "\n".join(batch.splitlines()[:3])
        self.assertEqual(self.repo.ok("apply", "--file", "-", "--dry-run", stdin=good)["written"], 0)
        self.assertEqual(self.repo.ok("status")["entities"], 0)
        self.assertEqual(self.repo.ok("apply", "--file", "-", stdin=good)["written"], 3)
        self.assertEqual(self.repo.ok("status")["relations"], 1)


class ReadTests(Base):
    def setUp(self):
        super().setUp()
        seed(self.repo)

    def test_find_by_source_path(self):
        self.assertEqual([e["id"] for e in self.repo.ok("find", "--source", "src/api/routes.py")],
                         ["area:checkout", "cap:place-order"])
        self.assertEqual(self.repo.ok("find", "--source", "src/billing"), [])

    def test_find_text_and_where(self):
        self.assertEqual([e["id"] for e in self.repo.ok("find", "--text", "request to")], ["term:order"])
        self.assertEqual([e["id"] for e in self.repo.ok("find", "--where", '{"name":"Order"}')], ["term:order"])

    def test_neighbors_depth(self):
        one = self.repo.ok("neighbors", "--id", "area:checkout", "--depth", "1")
        two = self.repo.ok("neighbors", "--id", "area:checkout", "--depth", "2")
        self.assertEqual({n["id"] for n in one["nodes"]}, {"area:checkout", "cap:place-order"})
        self.assertEqual({n["id"] for n in two["nodes"]}, {"area:checkout", "cap:place-order", "term:order"})

    def test_path(self):
        hops = self.repo.ok("path", "--from", "term:order", "--to", "area:checkout")
        self.assertEqual([h["rel"] for h in hops], ["changes", "part_of"])
        self.repo.ok("add", "--type", "Actor", "--props", '{"name":"Island","kind":"person"}')
        self.repo.fails("path", "--from", "actor:island", "--to", "area:checkout")

    def test_summary_lists_components(self):
        text = self.repo.ok("summary")
        self.assertIn("`area:checkout` Checkout", text)
        self.assertIn("3 entities, 2 relations", text)

    def test_validate_catches_schema_drift(self):
        schema_path = self.repo.root / ".ontology/schema.json"
        schema = json.loads(schema_path.read_text())
        schema["types"]["Concept"]["required"].append("states")
        schema_path.write_text(json.dumps(schema))
        out = self.repo.run("validate")
        self.assertEqual(out.returncode, 1)
        self.assertIn("term:order", out.stdout)

    def test_compact_preserves_state(self):
        self.repo.ok("update", "--id", "area:checkout", "--set", '{"summary":"Where buying happens"}')
        self.repo.ok("unlink", "--from", "cap:place-order", "--rel", "changes", "--to", "term:order")
        before = self.repo.ok("get", "--id", "area:checkout")
        self.repo.ok("compact")
        self.assertEqual(self.repo.ok("get", "--id", "area:checkout"), before)
        self.assertEqual(self.repo.ok("status")["relations"], 1)


class StaleTests(Base):
    def setUp(self):
        super().setUp()
        seed(self.repo)

    def stale_ids(self):
        return {e["id"]: e["status"] for e in self.repo.ok("stale")["entities"]}

    def test_fresh_after_seed(self):
        self.assertEqual(self.stale_ids(), {})

    def test_uncommitted_edit_then_verify(self):
        self.repo.write("src/api/routes.py", "def routes(): return 1\n")
        self.assertEqual(self.stale_ids(), {"area:checkout": "changed", "cap:place-order": "changed"})
        self.repo.ok("verify", "--id", "cap:place-order")
        self.assertEqual(self.stale_ids(), {"area:checkout": "changed"})
        self.repo.ok("verify", "--all")
        self.assertEqual(self.stale_ids(), {})

    def test_commit_of_verified_content_stays_fresh(self):
        self.repo.write("src/api/routes.py", "def routes(): return 2\n")
        self.repo.ok("verify", "--all")
        self.repo.commit("change")
        self.assertEqual(self.stale_ids(), {})

    def test_untracked_file_in_source_dir(self):
        self.repo.write("src/api/new_handler.py", "x = 1\n")
        self.assertEqual(self.stale_ids(), {"area:checkout": "changed"})

    def test_missing_source(self):
        (self.repo.root / "src/api/routes.py").unlink()
        self.assertEqual(self.stale_ids()["cap:place-order"], "missing")

    def test_unrelated_change_ignored(self):
        self.repo.write("src/billing/charge.py", "def charge(): return 0\n")
        self.repo.commit("billing")
        self.assertEqual(self.stale_ids(), {})


class NoGitTests(Base):
    use_git = False

    def test_works_without_git(self):
        seed(self.repo)
        self.assertEqual(self.repo.ok("stale")["stale"], 0)
        self.repo.write("src/api/routes.py", "changed\n")
        ids = {e["id"] for e in self.repo.ok("stale")["entities"]}
        self.assertEqual(ids, {"area:checkout", "cap:place-order"})


if __name__ == "__main__":
    unittest.main(verbosity=1)
