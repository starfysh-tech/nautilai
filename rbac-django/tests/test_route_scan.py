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


def test_include_is_followed_and_prefixed():
    """include("app.urls") resolves into composed full paths, not an opaque hop."""
    with tempfile.TemporaryDirectory() as root:
        write(root, "proj/urls.py", '''
from django.urls import path, include
urlpatterns = [path("api/", include("api.urls"))]
''')
        write(root, "api/urls.py", '''
from django.urls import path
from .views import UserView
urlpatterns = [path("users/", UserView.as_view())]
''')
        routes = scan_urlpatterns(root)
        print("test_include_is_followed_and_prefixed")
        check("one composed route", len(routes) == 1, routes)
        r = routes[0] if routes else None
        check("prefix composed", r and r["pattern"] == "api/users/", r)
        check("view resolved through include", r and r["view"] == "UserView", r)
        check("resolution is resolved", r and r["resolution"] == "resolved", r)
        check("no leftover unresolved include row",
              not any(x["resolution"] == "unresolved" for x in routes), routes)


def test_included_file_is_not_also_emitted_standalone():
    """A file reached via include() is not independently routable — no double count."""
    with tempfile.TemporaryDirectory() as root:
        write(root, "proj/urls.py", '''
from django.urls import path, include
urlpatterns = [path("api/", include("api.urls"))]
''')
        write(root, "api/urls.py", '''
from django.urls import path
from .views import UserView
urlpatterns = [path("users/", UserView.as_view())]
''')
        routes = scan_urlpatterns(root)
        print("test_included_file_is_not_also_emitted_standalone")
        check("bare 'users/' not emitted", by_pattern(routes, "users/") is None, routes)
        check("exactly one route total", len(routes) == 1, routes)


def test_ambiguous_or_missing_include_stays_unresolved():
    """Never guess: 0 or 2+ candidate modules must not produce an edge."""
    with tempfile.TemporaryDirectory() as root:
        write(root, "proj/urls.py", '''
from django.urls import path, include
urlpatterns = [
    path("a/", include("api.urls")),
    path("b/", include("nowhere.urls")),
]
''')
        # two files both matching "api/urls.py" — genuinely ambiguous
        write(root, "svc1/api/urls.py", 'from django.urls import path\nurlpatterns = [path("x/", X.as_view())]')
        write(root, "svc2/api/urls.py", 'from django.urls import path\nurlpatterns = [path("y/", Y.as_view())]')
        routes = scan_urlpatterns(root)
        print("test_ambiguous_or_missing_include_stays_unresolved")
        amb = by_pattern(routes, "a/")
        check("ambiguous include unresolved", amb and amb["resolution"] == "unresolved", amb)
        check("reason names the ambiguity",
              amb and ("ambiguous" in amb["reason"].lower() or "candidate" in amb["reason"].lower()), amb)
        missing = by_pattern(routes, "b/")
        check("missing module unresolved", missing and missing["resolution"] == "unresolved", missing)
        check("no invented edge for ambiguous include", amb and amb["view"] is None, amb)


def test_include_cycle_terminates():
    """A urls.py cycle must not hang or recurse forever."""
    with tempfile.TemporaryDirectory() as root:
        write(root, "a/urls.py", '''
from django.urls import path, include
urlpatterns = [path("b/", include("b.urls"))]
''')
        write(root, "b/urls.py", '''
from django.urls import path, include
urlpatterns = [path("a/", include("a.urls"))]
''')
        routes = scan_urlpatterns(root)
        print("test_include_cycle_terminates")
        check("cycle edge reported, not dropped", len(routes) >= 1, routes)
        check("every route still has a resolution",
              all(r.get("resolution") for r in routes), routes)
        # Assert the *visited* guard stopped it, not the depth cap. Without
        # this the depth cap silently covers for a removed cycle guard —
        # mutation testing caught exactly that.
        check("stopped by the cycle guard, naming it",
              any("cycle" in (r.get("reason") or "") for r in routes), routes)
        check("did not recurse to the depth cap",
              len(routes) <= 4, f"{len(routes)} routes — depth-capped, not cycle-caught")


def test_route_clusters_only_include_branching_shapes():
    """Convention #14 rule 1, enforced by the scanner rather than by prose."""
    with tempfile.TemporaryDirectory() as root:
        write(root, "app/urls.py", '''
from django.urls import path
from .views import ChartView, SoloView
urlpatterns = [
    path("charts/", ChartView.as_view()),
    path("charts/<int:pk>/", ChartView.as_view()),
    path("solo/", SoloView.as_view()),
]
''')
        write(root, "app/views.py", '''
from rest_framework import viewsets
class ChartView(viewsets.ModelViewSet):
    permission_classes = [IsStaff]
class SoloView(viewsets.ModelViewSet):
    permission_classes = [IsOwner]
''')
        routes = scan_urlpatterns(root)
        viewsets_ = rbac_scanner.scan_viewsets(root, set())[0]
        clusters = rbac_scanner.build_route_clusters(routes, viewsets_)
        print("test_route_clusters_only_include_branching_shapes")
        names = [c["view"] for c in clusters]
        check("multi-route view clustered", "ChartView" in names, names)
        check("single-route view NOT clustered", "SoloView" not in names, names)
        cv = next((c for c in clusters if c["view"] == "ChartView"), None)
        check("cluster carries its routes", cv and len(cv["routes"]) == 2, cv)
        check("cluster states why it qualified", cv and cv.get("reason"), cv)


def test_route_clusters_cap_and_report_omissions():
    """Capping is stated, never silent."""
    with tempfile.TemporaryDirectory() as root:
        write(root, "app/urls.py",
              "from django.urls import path\nurlpatterns = [\n"
              + "\n".join(f'    path("v{i}/a/", V{i}.as_view()),\n    path("v{i}/b/", V{i}.as_view()),'
                          for i in range(8))
              + "\n]\n")
        routes = scan_urlpatterns(root)
        clusters = rbac_scanner.build_route_clusters(routes, [], cap=5)
        print("test_route_clusters_cap_and_report_omissions")
        check("capped at 5", len(clusters) == 5, len(clusters))
        check("omission count exposed",
              rbac_scanner.count_omitted_clusters(routes, [], cap=5) == 3,
              rbac_scanner.count_omitted_clusters(routes, [], cap=5))


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
        test_include_is_followed_and_prefixed,
        test_included_file_is_not_also_emitted_standalone,
        test_ambiguous_or_missing_include_stays_unresolved,
        test_include_cycle_terminates,
        test_route_clusters_only_include_branching_shapes,
        test_route_clusters_cap_and_report_omissions,
        test_empty_scope,
    ):
        fn()
    print()
    if FAILURES:
        print(f"FAILED ({len(FAILURES)}): {', '.join(FAILURES)}")
        sys.exit(1)
    print("all route-scan tests passed")
