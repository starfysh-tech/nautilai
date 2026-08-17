#!/usr/bin/env python3
"""Self-contained tests for the URL-routing scan in rbac_scanner.py.

Builds throwaway Django-shaped fixtures under a temp dir — no Django, no
network, no third-party runner. Run directly:

    python3 rbac-django/tests/test_route_scan.py
"""
import importlib.util
import sys
import tempfile
from pathlib import Path

# Loaded by path: the scanner ships as a standalone script, not an importable
# package, so there is no module name to import it under.
_SCANNER = (
    Path(__file__).resolve().parents[1]
    / "skills" / "rbac-audit-django" / "scripts" / "rbac_scanner.py"
)
_spec = importlib.util.spec_from_file_location("rbac_scanner", _SCANNER)
assert _spec and _spec.loader, f"cannot load scanner at {_SCANNER}"
rbac_scanner = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(rbac_scanner)
scan_urlpatterns = rbac_scanner.scan_urlpatterns

FAILURES: list[str] = []


def check(label: str, cond: object, detail: object = "") -> None:
    if cond:
        print(f"  ok   {label}")
    else:
        print(f"  FAIL {label} {detail}")
        FAILURES.append(label)


def by_pattern(routes: list[dict], pattern: object) -> dict | None:
    for r in routes:
        if r["pattern"] == pattern:
            return r
    return None


def write(root: str, rel: str, body: str) -> Path:
    p = Path(root) / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(body)
    return p


def test_resolvable_views():
    """path()/re_path() pointing at a real view class resolve to that view."""
    with tempfile.TemporaryDirectory() as root:
        write(root, "app/urls.py", '''
from django.urls import path, re_path
from .views import UserViewSet
from . import views

urlpatterns = [
    path("users/", UserViewSet.as_view()),
    path("orders/", views.OrderView.as_view()),
    re_path(r"^legacy/(?P<pk>[0-9]+)/$", views.LegacyView.as_view()),
]
''')
        routes = scan_urlpatterns(root)
        print("test_resolvable_views")
        check("finds 3 routes", len(routes) == 3, f"got {len(routes)}")

        u = by_pattern(routes, "users/")
        check("direct import view name", u and u["view"] == "UserViewSet", u)
        check("direct import resolved", u and u["resolution"] == "resolved", u)

        o = by_pattern(routes, "orders/")
        check("dotted view name", o and o["view"] == "OrderView", o)

        lg = by_pattern(routes, r"^legacy/(?P<pk>[0-9]+)/$")
        check("re_path captured", lg is not None, routes)
        check("re_path kind", lg and lg["kind"] == "re_path", lg)

        check("file recorded", all(r["file"].endswith("app/urls.py") for r in routes), routes)
        check("line recorded", all(isinstance(r["line"], int) and r["line"] > 0 for r in routes), routes)


def test_router_register():
    """DRF router.register() is inferred, not treated as a plain path()."""
    with tempfile.TemporaryDirectory() as root:
        write(root, "api/urls.py", '''
from rest_framework.routers import DefaultRouter
from .views import PatientViewSet

router = DefaultRouter()
router.register(r"patients", PatientViewSet, basename="patient")
router.register("visits", VisitViewSet)

urlpatterns = router.urls
''')
        routes = scan_urlpatterns(root)
        print("test_router_register")
        check("finds 2 router routes", len(routes) == 2, f"got {len(routes)}")

        p = by_pattern(routes, "patients")
        check("router view name", p and p["view"] == "PatientViewSet", p)
        check("router kind", p and p["kind"] == "router", p)
        check("router-inferred resolution", p and p["resolution"] == "router-inferred", p)
        check("router reason present", p and p.get("reason"), p)

        v = by_pattern(routes, "visits")
        check("non-raw-string prefix", v and v["view"] == "VisitViewSet", v)


def test_unresolved_hops_are_reported_not_dropped():
    """Convention #14 rule 3: what can't be resolved is rendered, never omitted."""
    with tempfile.TemporaryDirectory() as root:
        write(root, "proj/urls.py", '''
from django.urls import path, include

urlpatterns = [
    path("api/", include("api.urls")),
    path("legacy/", "app.views.legacy_view"),
    path(dynamic_prefix(), SomeView.as_view()),
]
''')
        routes = scan_urlpatterns(root)
        print("test_unresolved_hops_are_reported_not_dropped")
        check("nothing dropped", len(routes) == 3, f"got {len(routes)}")

        inc = by_pattern(routes, "api/")
        check("include unresolved", inc and inc["resolution"] == "unresolved", inc)
        check("include reason names include", inc and "include" in inc["reason"].lower(), inc)

        strv = by_pattern(routes, "legacy/")
        check("string view unresolved", strv and strv["resolution"] == "unresolved", strv)

        dyn = [r for r in routes if r["resolution"] == "unresolved" and r["pattern"] is None]
        check("dynamic prefix kept with null pattern", len(dyn) == 1, routes)
        check("every unresolved has a reason",
              all(r.get("reason") for r in routes if r["resolution"] == "unresolved"), routes)


def test_ignores_non_url_files_and_bad_syntax():
    """Only urls.py / urls packages are read, and a broken file can't crash the scan."""
    with tempfile.TemporaryDirectory() as root:
        write(root, "app/views.py", 'urlpatterns = [path("nope/", X.as_view())]')
        write(root, "app/urls/routes.py", '''
from django.urls import path
from .views import PkgView
urlpatterns = [path("pkg/", PkgView.as_view())]
''')
        write(root, "app/urls.py", "urlpatterns = [ this is not python (((")
        write(root, "tests/urls.py", 'urlpatterns = [path("t/", T.as_view())]')
        routes = scan_urlpatterns(root)
        print("test_ignores_non_url_files_and_bad_syntax")
        check("views.py ignored", by_pattern(routes, "nope/") is None, routes)
        check("urls/ package read", by_pattern(routes, "pkg/") is not None, routes)
        check("tests/ excluded", by_pattern(routes, "t/") is None, routes)
        check("unparseable file skipped, no crash", True)


def test_empty_scope():
    with tempfile.TemporaryDirectory() as root:
        print("test_empty_scope")
        check("no urls.py yields empty list", scan_urlpatterns(root) == [])


if __name__ == "__main__":
    for fn in (
        test_resolvable_views,
        test_router_register,
        test_unresolved_hops_are_reported_not_dropped,
        test_ignores_non_url_files_and_bad_syntax,
        test_empty_scope,
    ):
        fn()
    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}): {', '.join(FAILURES)}")
        sys.exit(1)
    print("all route-scan tests passed")
