# Changelog

## [2.19.0](https://github.com/starfysh-tech/nautilai/compare/v2.18.6...v2.19.0) (2026-07-17)


### Features

* **hermes:** fan out review skills via delegate_task ([e7fd4e5](https://github.com/starfysh-tech/nautilai/commit/e7fd4e5dc76a674e4d6c592bfe80a59748035014))

## [2.18.6](https://github.com/starfysh-tech/nautilai/compare/v2.18.5...v2.18.6) (2026-07-15)


### Bug Fixes

* **commitcraft:** drop bash 4 associative arrays for macos support ([2c3d3cf](https://github.com/starfysh-tech/nautilai/commit/2c3d3cf9473c6b6f3f81f155d84fc4515dad9071))

## [2.18.5](https://github.com/starfysh-tech/nautilai/compare/v2.18.4...v2.18.5) (2026-07-15)


### Bug Fixes

* **cc-validate-hooks:** report invalid json as an error, not a crash ([5237b75](https://github.com/starfysh-tech/nautilai/commit/5237b758842b0c6abece32c6bd0361c3b870e505))
* **cc-validate-hooks:** report unreadable files as an error, not a crash ([19452e3](https://github.com/starfysh-tech/nautilai/commit/19452e3de4ae3d1d0039fb283c3cc606b7f22e5f))

## [2.18.4](https://github.com/starfysh-tech/nautilai/compare/v2.18.3...v2.18.4) (2026-07-13)


### Bug Fixes

* **pr-comment-review:** stop the injection defense tripping the scanner ([e7cf160](https://github.com/starfysh-tech/nautilai/commit/e7cf160f0f95fc48645acfaf3dd66c0a001debdb))

## [2.18.3](https://github.com/starfysh-tech/nautilai/compare/v2.18.2...v2.18.3) (2026-07-13)


### Bug Fixes

* **commitcraft:** find gh when the sandbox path omits homebrew ([26c9d4c](https://github.com/starfysh-tech/nautilai/commit/26c9d4cc9fa7c0b54ded895bea9ad1b15c09f170))

## [2.18.2](https://github.com/starfysh-tech/nautilai/compare/v2.18.1...v2.18.2) (2026-07-12)


### Bug Fixes

* **commitcraft:** cut the scanner rationale out of skill.md ([a022178](https://github.com/starfysh-tech/nautilai/commit/a02217854b86ff3125bf0a42038474f68fa69fa6))

## [2.18.1](https://github.com/starfysh-tech/nautilai/compare/v2.18.0...v2.18.1) (2026-07-12)


### Bug Fixes

* **commitcraft:** drop setup from the hermes bundle, blocked by scanner ([2593d82](https://github.com/starfysh-tech/nautilai/commit/2593d82ca92e993f20b744aacd8f18f450018564))

## [2.18.0](https://github.com/starfysh-tech/nautilai/compare/v2.17.0...v2.18.0) (2026-07-12)


### Features

* **commitcraft:** run in hermes agent alongside claude code ([3a7abe0](https://github.com/starfysh-tech/nautilai/commit/3a7abe0458f8e388ba6b87106bdbd9464199f90e))


### Bug Fixes

* **commitcraft:** guard the jq dependency on the github issue path ([b25669f](https://github.com/starfysh-tech/nautilai/commit/b25669f7bf61b5b66abb197d88d2d2fdae449ebf))

## [2.17.0](https://github.com/starfysh-tech/nautilai/compare/v2.16.2...v2.17.0) (2026-07-09)


### Features

* **relay:** add done-criterion and curation hints to handoff ([8202dca](https://github.com/starfysh-tech/nautilai/commit/8202dca770f642b80387fbca1e8450c94023fa74))

## [2.16.2](https://github.com/starfysh-tech/nautilai/compare/v2.16.1...v2.16.2) (2026-07-08)


### Bug Fixes

* **commitcraft:** raise commit subject cap to 72 ([41e2a12](https://github.com/starfysh-tech/nautilai/commit/41e2a121730d6401bc3507aa32c3485a88263a48))

## [2.16.1](https://github.com/starfysh-tech/nautilai/compare/v2.16.0...v2.16.1) (2026-07-08)


### Bug Fixes

* **docs:** self-host anime.js instead of cdn ([72195b6](https://github.com/starfysh-tech/nautilai/commit/72195b60545c9e67ab37fb65df7cf67b4dc8ee42))

## [2.16.0](https://github.com/starfysh-tech/nautilai/compare/v2.15.0...v2.16.0) (2026-07-08)


### Features

* add community-health files ([1c64076](https://github.com/starfysh-tech/nautilai/commit/1c64076fbf68f722aa28741c8ec1e5d4f66f6f69))
* community-health files and pr-template respect ([37aa4b9](https://github.com/starfysh-tech/nautilai/commit/37aa4b9b2c35d97af3062bfe69e00e28b016662c))


### Bug Fixes

* **ci:** pin commitlint action versions ([fcad30b](https://github.com/starfysh-tech/nautilai/commit/fcad30b81bf0f6ea602a46c55731cbbfd0811d9e))
* **commitcraft:** fill repo pr template instead of overwriting ([7050bfa](https://github.com/starfysh-tech/nautilai/commit/7050bfacea96184afcfd18bc79388b58448c88b1))

## [2.15.0](https://github.com/starfysh-tech/nautilai/compare/v2.14.4...v2.15.0) (2026-07-08)


### Features

* **cc-skill-audit:** merge scored scorecard into sweep mode ([c961735](https://github.com/starfysh-tech/nautilai/commit/c9617357ff99c0319b6cefa257ad66b893cf6f48))
* **cc-skill-audit:** merge scored scorecard into sweep mode ([f99bc43](https://github.com/starfysh-tech/nautilai/commit/f99bc43f33907e46bb5c53d87b09ee6da58cd2f8))


### Bug Fixes

* **cc-skill-audit:** close gaps found by clean-agent validation ([b6948bd](https://github.com/starfysh-tech/nautilai/commit/b6948bddfcf6b607750537ceac4ccd7ac2d954d1))
* **cc-skill-audit:** fail fast when workflow args are missing ([c93bfa6](https://github.com/starfysh-tech/nautilai/commit/c93bfa69526a0ab46488f41e2bc343024a7662b2))

## [2.14.4](https://github.com/starfysh-tech/nautilai/compare/v2.14.3...v2.14.4) (2026-07-08)


### Bug Fixes

* adopt hardening lessons from no-mistakes review ([2e6cc83](https://github.com/starfysh-tech/nautilai/commit/2e6cc83520c60bf457d20c2d16658b27ed961e1b))
* adopt hardening lessons from no-mistakes review ([7e52c6a](https://github.com/starfysh-tech/nautilai/commit/7e52c6aa64a198dc40ea7844e713bc422c0de60e))
* **autodev:** keep transient cap alive across record-failure ([e4210a5](https://github.com/starfysh-tech/nautilai/commit/e4210a55fbd9bfe4237f81bd3a9a24dc239a76e0))

## [2.14.3](https://github.com/starfysh-tech/nautilai/compare/v2.14.2...v2.14.3) (2026-07-08)


### Bug Fixes

* apply marketplace-wide plugin review fixes ([2b0b6f7](https://github.com/starfysh-tech/nautilai/commit/2b0b6f7992126f0e3a2e3b3f302cfbfd8d3fdf21))
* apply marketplace-wide plugin review fixes ([8f8cac8](https://github.com/starfysh-tech/nautilai/commit/8f8cac8574906dda11706a6afe937cb28aa3fa6e))
* **rbac-django:** strip carriage returns from role bullets ([e8d7c19](https://github.com/starfysh-tech/nautilai/commit/e8d7c19096acbec35d2caedc80cde9f7ff4539d4))

## [2.14.2](https://github.com/starfysh-tech/nautilai/compare/v2.14.1...v2.14.2) (2026-07-06)


### Bug Fixes

* **relay:** drop staleness expiry on clear pickup ([49bd9e0](https://github.com/starfysh-tech/nautilai/commit/49bd9e056678675dcd767f53db0744bc0fd537eb))
* **relay:** drop staleness expiry on clear pickup ([1c822ad](https://github.com/starfysh-tech/nautilai/commit/1c822ad23f92f31fb29fab37106c9e430e7650ac))

## [2.14.1](https://github.com/starfysh-tech/nautilai/compare/v2.14.0...v2.14.1) (2026-07-06)


### Bug Fixes

* **relay:** de-nest pem scrub quantifier (redos) ([0d42084](https://github.com/starfysh-tech/nautilai/commit/0d420846f6ebfbb1cc16f0ab5312c0de0d447e7c))
* **relay:** de-nest pem scrub quantifier (redos) ([4db2047](https://github.com/starfysh-tech/nautilai/commit/4db2047c38bb8457d6c1fa7bb56350db1ecacde8))

## [2.14.0](https://github.com/starfysh-tech/nautilai/compare/v2.13.0...v2.14.0) (2026-07-06)


### Features

* **relay:** broaden secret scrub, generalize skip-prefix ([d74b104](https://github.com/starfysh-tech/nautilai/commit/d74b10478fbb64668359352dc5a762770d0bd77e))
* **relay:** fast-follow scrub, skip-prefix, and eval breadth ([3f532bb](https://github.com/starfysh-tech/nautilai/commit/3f532bbbd87baa18ad2b184b9319423d4dc92a02))


### Bug Fixes

* **relay:** remove fabricated survey from skip-prefix comment ([96e2e63](https://github.com/starfysh-tech/nautilai/commit/96e2e634e520f7fd30656c2802bcd8529c334fd9))

## [2.13.0](https://github.com/starfysh-tech/nautilai/compare/v2.12.0...v2.13.0) (2026-07-05)


### Features

* **relay:** public-readiness controls and self-diagnosis ([2e121b2](https://github.com/starfysh-tech/nautilai/commit/2e121b2d6cfe186d9d09edada2463ab08eee25c8))
* **relay:** public-readiness controls and self-diagnosis ([2670f6c](https://github.com/starfysh-tech/nautilai/commit/2670f6c3fd4bf4ae0010e5a87291c8bbdd361203))


### Bug Fixes

* **relay:** gnu-first stat chains, doctor traps ([7b70f0f](https://github.com/starfysh-tech/nautilai/commit/7b70f0f45768ae075085b0f1f5fd83727a9cd165))

## [2.12.0](https://github.com/starfysh-tech/nautilai/compare/v2.11.0...v2.12.0) (2026-07-05)


### Features

* **relay:** haiku narrative layer for assistant-turn semantics ([4b1c049](https://github.com/starfysh-tech/nautilai/commit/4b1c049f57297afa68765fdae9eb86657da8288f))
* **relay:** haiku narrative layer for assistant-turn semantics ([792aa96](https://github.com/starfysh-tech/nautilai/commit/792aa96945ffb978f28a8fd76eb1582dccf37658))


### Bug Fixes

* **relay:** short-circuit failed chunks, plug temp leaks ([854dabe](https://github.com/starfysh-tech/nautilai/commit/854dabe1f03cf9a33c0a04cf84472566f416a1e9))

## [2.11.0](https://github.com/starfysh-tech/nautilai/compare/v2.10.0...v2.11.0) (2026-07-05)


### Features

* **relay:** recover compaction losses via /handoff recover ([54f1bd5](https://github.com/starfysh-tech/nautilai/commit/54f1bd5f0976363c5be51675ef151624b07b2a72))
* **relay:** recover compaction losses via /handoff recover ([de74ac8](https://github.com/starfysh-tech/nautilai/commit/de74ac896138d5f89675542e061d1149339059a7))


### Bug Fixes

* **relay:** handle compaction boundary on transcript line 1 ([612bb9a](https://github.com/starfysh-tech/nautilai/commit/612bb9a115c9556698893fe8eff1bafd096d6736))

## [2.10.0](https://github.com/starfysh-tech/nautilai/compare/v2.9.3...v2.10.0) (2026-07-05)


### Features

* **relay:** transcript-grounded handoff auto-pickup ([2c41031](https://github.com/starfysh-tech/nautilai/commit/2c4103146b5970ac1e23abf7a1a934bc84a6a01e))
* **relay:** transcript-grounded handoff with auto-pickup ([9317198](https://github.com/starfysh-tech/nautilai/commit/9317198cb3fb6735c6bc55933b4afa01cf9a6785))


### Bug Fixes

* **relay:** filter harness-injected messages structurally ([3a6b71e](https://github.com/starfysh-tech/nautilai/commit/3a6b71eaae1967fec54c2780f0f16bc312de16df))
* **relay:** harden pickup and extractor per review ([e5bf1a0](https://github.com/starfysh-tech/nautilai/commit/e5bf1a0ab4bacc9a50a3edf169f1b61b1b10e6ec))


### Performance

* **relay:** single-pass message formatting, no test sleep ([06507f4](https://github.com/starfysh-tech/nautilai/commit/06507f46f6f979f53d4bf0248f46789fc0c3b7da))

## [2.9.3](https://github.com/starfysh-tech/nautilai/compare/v2.9.2...v2.9.3) (2026-07-04)


### Bug Fixes

* **commitcraft:** hide docs in shipped release template ([3ed0183](https://github.com/starfysh-tech/nautilai/commit/3ed01834552ee51626980f1614b0f81bb679dde1))

## [2.9.2](https://github.com/starfysh-tech/nautilai/compare/v2.9.1...v2.9.2) (2026-07-04)


### Documentation

* **backlog:** add autodev installed-plugin dogfood run ([0fdd358](https://github.com/starfysh-tech/nautilai/commit/0fdd358d995c3e3ca4dc2f1900e9787df85cbbb7))
* **backlog:** add autodev installed-plugin dogfood run ([760c534](https://github.com/starfysh-tech/nautilai/commit/760c53418e71c59849d07a1ae5a6c9677516077e))
* **backlog:** link file references in autodev entry ([0ab6f40](https://github.com/starfysh-tech/nautilai/commit/0ab6f40cbd5f5e1a840e1bad69905086eb894581))

## [2.9.1](https://github.com/starfysh-tech/nautilai/compare/v2.9.0...v2.9.1) (2026-07-03)


### Bug Fixes

* **pr-comment-review:** treat comment bodies as untrusted ([8b857c4](https://github.com/starfysh-tech/nautilai/commit/8b857c4d0eb38d9f1139f6582853b95cb91b1226))

## [2.9.0](https://github.com/starfysh-tech/nautilai/compare/v2.8.1...v2.9.0) (2026-07-03)


### Features

* **autodev:** add bounded autonomous development plugin ([e4429f6](https://github.com/starfysh-tech/nautilai/commit/e4429f6990dde4cfe7185bcd0ffa6f2eebd30cb5))
* **autodev:** add bounded autonomous development plugin ([4832f56](https://github.com/starfysh-tech/nautilai/commit/4832f56493ca3a2cac0ecfad63715ba442809c65))
* **autodev:** gate lane completion behind independent review ([ec6105a](https://github.com/starfysh-tech/nautilai/commit/ec6105a158209cc435d2ac40ac049addf6e5b69f))


### Bug Fixes

* **autodev:** apply findings from first live validation run ([24a5c94](https://github.com/starfysh-tech/nautilai/commit/24a5c94f50c03324e6c1d71798eb98ee20d84148))
* **autodev:** apply run-5 findings from live review-gate loop ([2085fa7](https://github.com/starfysh-tech/nautilai/commit/2085fa7c15dc30dce9346ac28076a0365740315e))
* **autodev:** harden worktree lifecycle and jq-less verify ([6adf31f](https://github.com/starfysh-tech/nautilai/commit/6adf31fc0717ec404e5499626a9a7ac617bc339b))
* **autodev:** serialize state writes, apply run-2 findings ([ad12fe9](https://github.com/starfysh-tech/nautilai/commit/ad12fe93945c8c86b5104864ae9f8831c86e68ef))
* **autodev:** unstick lanes after recovered baseline ([9a254b9](https://github.com/starfysh-tech/nautilai/commit/9a254b99f5c3f24ce0e38076e2a85ed67929ddaf))


### Documentation

* **autodev:** close failure-path scenario after run 4 ([fb0eb06](https://github.com/starfysh-tech/nautilai/commit/fb0eb069301b087bf0593539b66622f6ea67f28e))
* **autodev:** move run 5 venue to linktrail ([170c3f7](https://github.com/starfysh-tech/nautilai/commit/170c3f73a8cabdf768a320a081fe163870acb33b))
* **autodev:** position against /goal, spec run 4 ([6ec5871](https://github.com/starfysh-tech/nautilai/commit/6ec5871ad512a64c5043d89c2a4790450a4276eb))
* **autodev:** publish validated scope and readiness backlog ([ce0d3bd](https://github.com/starfysh-tech/nautilai/commit/ce0d3bd7c2fd211fc60d551b1c9dc3969581b507))
* **autodev:** spec run 3 as red-first failure-path validation ([bf41d62](https://github.com/starfysh-tech/nautilai/commit/bf41d62cbd2e77191b6b834ead2345fb4d9ff3e8))
* **claude:** tighten commitcraft mandate wording ([1b8b2f1](https://github.com/starfysh-tech/nautilai/commit/1b8b2f1ab8ade69cad4e174625fea05c3b69f81a))

## [2.8.1](https://github.com/starfysh-tech/nautilai/compare/v2.8.0...v2.8.1) (2026-06-26)


### Documentation

* **claude:** document test suite and path rule ([89172ed](https://github.com/starfysh-tech/nautilai/commit/89172edcfe0a97e1e4b495e004c7ab8dc74d0385))

## [2.8.0](https://github.com/starfysh-tech/nautilai/compare/v2.7.3...v2.8.0) (2026-06-25)


### Features

* **commitcraft:** honor repo changelog-sections config ([c1a75ce](https://github.com/starfysh-tech/nautilai/commit/c1a75ce75f6dc979b6d0c1b940bb7f0a6d1091ab))
* **commitcraft:** honor repo changelog-sections config ([43191ef](https://github.com/starfysh-tech/nautilai/commit/43191ef267ca10c6434cbb4333a056b84586115c))


### Bug Fixes

* **commitcraft:** read changelog-sections from either layout ([84ae30d](https://github.com/starfysh-tech/nautilai/commit/84ae30dad0d4efe9785f52659247d058e358581a))


### Documentation

* **commitcraft:** note config-driven changelog sections ([c77ab3f](https://github.com/starfysh-tech/nautilai/commit/c77ab3f048acd845c6ee40396e7393803e8d5049))

## [2.7.3](https://github.com/starfysh-tech/nautilai/compare/v2.7.2...v2.7.3) (2026-06-25)


### Bug Fixes

* **commitcraft:** don't mask git log errors in analyzer ([2082930](https://github.com/starfysh-tech/nautilai/commit/2082930e591de677d3d361364848115d4f63ef77))
* **commitcraft:** stop grep -c double-printing zero ([dc3a0dd](https://github.com/starfysh-tech/nautilai/commit/dc3a0dd0f81f8095af81c86c6b121eeaeafa7f26))
* **commitcraft:** stop grep -c double-printing zero ([2fcdba4](https://github.com/starfysh-tech/nautilai/commit/2fcdba4a62ef68769787f48739d8cf1528634354))

## [2.7.2](https://github.com/starfysh-tech/nautilai/compare/v2.7.1...v2.7.2) (2026-06-25)


### Bug Fixes

* **commitcraft:** defer to release-please only when functional ([38b8dc2](https://github.com/starfysh-tech/nautilai/commit/38b8dc2e68d316241ff139f9ba84c2198b3c7b26))
* **commitcraft:** harden release-please detection ([140e175](https://github.com/starfysh-tech/nautilai/commit/140e175fe39cfba5f0cde88fd5687caa9320e3a2))

## [2.7.1](https://github.com/starfysh-tech/nautilai/compare/v2.7.0...v2.7.1) (2026-06-25)


### Bug Fixes

* address review on restored scripts ([e81a758](https://github.com/starfysh-tech/nautilai/commit/e81a758965d50abb4ef1249a362dd62b218ef37e))
* restore dep-review parallelism, portable evals ([255eaeb](https://github.com/starfysh-tech/nautilai/commit/255eaebc95c284078f26cdae64c84b8657cd158b))
* restore dropped scripts, fix regressions ([9e58a47](https://github.com/starfysh-tech/nautilai/commit/9e58a47bebf688cb1ef403299582a79d8934ae91))
* restore dropped skill scripts to parity ([5b65640](https://github.com/starfysh-tech/nautilai/commit/5b65640ee81107fb8a331dc1fb5738aeae5264b7))

## [2.7.0](https://github.com/starfysh-tech/nautilai/compare/v2.6.0...v2.7.0) (2026-06-25)


### Features

* port five internal skills as marketplace plugins ([dc7db1a](https://github.com/starfysh-tech/nautilai/commit/dc7db1a1f0d8662f691779c81af14ae16e48b447))
* port five internal skills as marketplace plugins ([1791e8d](https://github.com/starfysh-tech/nautilai/commit/1791e8d5cc65a386912e4aff8223809063896dd6))


### Bug Fixes

* harden bundled scripts from pr review ([f175d6f](https://github.com/starfysh-tech/nautilai/commit/f175d6f55fa2c848b9831280c41a76ced078ac75))
* scope release auto-merge to the repository ([b5edcd6](https://github.com/starfysh-tech/nautilai/commit/b5edcd6cf1af333918a7d5fa8159f4db1069d844))
* scope release auto-merge to the repository ([6d02813](https://github.com/starfysh-tech/nautilai/commit/6d028137353dab20828d158474d155ad7d71dc80))


### Documentation

* document automated release and validate gate ([721e044](https://github.com/starfysh-tech/nautilai/commit/721e0449999cd6f072ba1620e9a331cf365515e6))
* document automated release and validate gate ([d65a5b7](https://github.com/starfysh-tech/nautilai/commit/d65a5b7414486f357388e9f98e3e69af88a262ac))

## [2.6.0](https://github.com/starfysh-tech/nautilai/compare/v2.5.0...v2.6.0) (2026-06-25)


### Features

* **pr-review-deep:** add deep code-quality review plugin ([6a91ece](https://github.com/starfysh-tech/nautilai/commit/6a91ecef103ef0f8462010c00a9dc36f881938f1))
* **pr-review-deep:** add deep code-quality review plugin ([ae7b742](https://github.com/starfysh-tech/nautilai/commit/ae7b74257c6a71158ec84264f1b03ad3b8969157))

## [2.5.0](https://github.com/starfysh-tech/nautilai/compare/v2.4.1...v2.5.0) (2026-06-24)


### Features

* **conventions:** add shoals and a curated plugin changelog ([be632a5](https://github.com/starfysh-tech/nautilai/commit/be632a563c521dbd2edcce4a7ca2231ad291991d))
* **conventions:** add shoals for auto-captured corrections ([e5a5b14](https://github.com/starfysh-tech/nautilai/commit/e5a5b141e8156b4648ae0c73e8650a3e21ac0e0e))
* **conventions:** standardize finding dispositions ([1113667](https://github.com/starfysh-tech/nautilai/commit/111366768d84109fade78fb32b0ba1cf16009b06))
* **conventions:** standardize finding dispositions ([69bca7f](https://github.com/starfysh-tech/nautilai/commit/69bca7fa7d4916dfb1df5f17e30f405fca1cc50a))


### Documentation

* **changelog:** backfill plugin history, why over what ([54a0569](https://github.com/starfysh-tech/nautilai/commit/54a05694bc8920e4ff7d157d67186be14ae1313a))
* **conventions:** clarify shoal entry format ([ae4468d](https://github.com/starfysh-tech/nautilai/commit/ae4468d3918ba959021ab8e7c52e29a6191654ba))

## [2.4.1](https://github.com/starfysh-tech/nautilai/compare/v2.4.0...v2.4.1) (2026-06-21)


### Bug Fixes

* **cc-validate-hooks:** accept all valid hook types ([f3296af](https://github.com/starfysh-tech/nautilai/commit/f3296af7055589f64aea7ac10eda85471e860ace))
* **cc-validate-hooks:** error on non-string hook type ([84ae21a](https://github.com/starfysh-tech/nautilai/commit/84ae21a3ced5a766bc57f3ba4a73fd9faff28a8a))

## [2.4.0](https://github.com/starfysh-tech/nautilai/compare/v2.3.0...v2.4.0) (2026-06-21)


### Features

* **phi-scan:** add opt-in write-time phi guard hook ([c735d91](https://github.com/starfysh-tech/nautilai/commit/c735d9195b1961e45f7e425919ebcc1da87ea66b))
* **phi-scan:** add opt-in write-time phi guard hook ([7244e02](https://github.com/starfysh-tech/nautilai/commit/7244e02aea781eaf3bee8b59a9aca637de3991be))


### Bug Fixes

* **phi-scan:** fail open on non-dict hook payload ([2d6d0ce](https://github.com/starfysh-tech/nautilai/commit/2d6d0ceb94bb920da7a0fd816091a0073cc7381b))


### Performance

* **phi-scan:** gate guard on env before importing scanner ([89d5228](https://github.com/starfysh-tech/nautilai/commit/89d522869d52d43f53ef4a872189fd7865a60028))


### Documentation

* **phi-scan:** note matcher/content_for_tool sync in guard ([32d6b76](https://github.com/starfysh-tech/nautilai/commit/32d6b768dee0cdfbfdee8ae2d445022e614bb369))

## [2.3.0](https://github.com/starfysh-tech/nautilai/compare/v2.2.0...v2.3.0) (2026-06-21)


### Features

* add cc-adoption-audit plugin ([5419086](https://github.com/starfysh-tech/nautilai/commit/5419086856726f739e070bffcca0d470149827ae))
* add cc-adoption-audit plugin ([4730210](https://github.com/starfysh-tech/nautilai/commit/4730210f494a43b69be758c438a9bfc2703ffc07))
* add cc-validate-hooks plugin ([0fd22c4](https://github.com/starfysh-tech/nautilai/commit/0fd22c449655a639513c0f55e9a457d04c7b6b55))
* add cc-validate-hooks plugin ([434a038](https://github.com/starfysh-tech/nautilai/commit/434a038188cd722b974c2183ba20cda2d3c4fe7e))
* add pr-comment-review plugin ([b673ed6](https://github.com/starfysh-tech/nautilai/commit/b673ed67cae7d4b6f92a937c63a0c6c5fa0fe691))
* add pr-comment-review plugin ([f7029ac](https://github.com/starfysh-tech/nautilai/commit/f7029aca66e45dad2ae63a5c9b24def56a268da7))
* **cc-adoption-audit:** add what's-new section ([2958e1c](https://github.com/starfysh-tech/nautilai/commit/2958e1cfaff07931627ade951c9860f5acc1e3de))
* **cc-adoption-audit:** add what's-new section ([4f5025b](https://github.com/starfysh-tech/nautilai/commit/4f5025b73d18e10ee880a66007940f1993f81003))
* **cc-skill-audit:** add skill-authoring audit plugin ([520999c](https://github.com/starfysh-tech/nautilai/commit/520999c9e9847b1ca1ff1d3b81efa3e51b4eeeff))
* **cc-skill-audit:** add skill-authoring audit plugin ([e6e9c3d](https://github.com/starfysh-tech/nautilai/commit/e6e9c3dbc9c1eba7427bb5acb51df985335a26b7))
* **landing:** redesign marketing page with nautilus hero ([fb14012](https://github.com/starfysh-tech/nautilai/commit/fb14012bf9554610df68d5148ee677dfdba16a07))
* **landing:** redesign marketing page with nautilus hero ([ef6d332](https://github.com/starfysh-tech/nautilai/commit/ef6d332679850bcaf01c83cc5c164cbd2a65d28b))
* **phi-scan:** add phi/hipaa scanner plugin ([ba74ec5](https://github.com/starfysh-tech/nautilai/commit/ba74ec55f5354ff10a2b2af263c7361279d43b1e))
* **phi-scan:** add phi/hipaa scanner plugin ([307ca3b](https://github.com/starfysh-tech/nautilai/commit/307ca3b2dabead43e0080845de23e6c40993365a))
* **review-plan:** add plan validation plugin ([4cc3825](https://github.com/starfysh-tech/nautilai/commit/4cc38257972ed827dacc124ba6fe11bf01740e51))
* **review-plan:** add plan validation plugin ([a94471b](https://github.com/starfysh-tech/nautilai/commit/a94471b878531aad3d578c90a3d374fa33e00784))


### Bug Fixes

* **cc-adoption-audit:** resolve home dir before file reads ([92dc30b](https://github.com/starfysh-tech/nautilai/commit/92dc30b22c5931755a6fe067075cec6de0264772))
* **cc-validate-hooks:** harden validation + fix command hint ([a5d31dd](https://github.com/starfysh-tech/nautilai/commit/a5d31dd0475b2e63e9e3c71eeaffe55fd3603c00))
* **landing:** address review — mobile accordion, curve, cleanup ([bd8f8f1](https://github.com/starfysh-tech/nautilai/commit/bd8f8f148c7a74908f25c6d989847ec49d85cae1))
* **phi-scan:** address scanner robustness and portability ([30d6992](https://github.com/starfysh-tech/nautilai/commit/30d6992d5ff2b75259c7328c548446e9e54b2a1c))
* **review-plan:** declare the head command in allowed-tools ([3a194cd](https://github.com/starfysh-tech/nautilai/commit/3a194cd0cb84f2d99cd20018cfb4a12559b1edd8))


### Documentation

* correct release-please config reference ([30a20c0](https://github.com/starfysh-tech/nautilai/commit/30a20c0e24ce31f16c90d6eb922fbf23767852ce))

## [2.2.0](https://github.com/starfysh-tech/nautilai/compare/v2.1.0...v2.2.0) (2026-06-18)


### Features

* add handoff plugin and one-click command copy ([5a59fef](https://github.com/starfysh-tech/nautilai/commit/5a59fefacbf20063861b0568a1617081b7b568fe))
* add handoff plugin and one-click command copy ([4313dd4](https://github.com/starfysh-tech/nautilai/commit/4313dd4bc9573d2d05febdc946304e90c9a395e9))

## [2.1.0](https://github.com/starfysh-tech/nautilai/compare/v2.0.0...v2.1.0) (2026-06-18)


### Features

* enforcement provisioning, tracker abstraction, and agent-native setup ([bbc25e3](https://github.com/starfysh-tech/nautilai/commit/bbc25e34e9b83f70af27c68f0b62be909d353fb1))
* initial nautilai marketplace with commitcraft plugin ([963d5e6](https://github.com/starfysh-tech/nautilai/commit/963d5e648d31fc0663c01c333dcccec0ad533f6d))
* **issues:** add tracker-aware and ref-only modes ([64d7227](https://github.com/starfysh-tech/nautilai/commit/64d722713137d51d5b18b2b1e19629dcb232cce7))
* **setup:** add protection, tracker, headless mode ([9cc2a6c](https://github.com/starfysh-tech/nautilai/commit/9cc2a6ce18fb1a8c71285d6bfe1baaf3286134d8))


### Bug Fixes

* **pages:** meet aa contrast and secure links ([06078cb](https://github.com/starfysh-tech/nautilai/commit/06078cb7c0d432377c7d86c4be94cdf60e40c8a0))
* **pages:** restore mobile gutters and clean the hero ([bfab3fc](https://github.com/starfysh-tech/nautilai/commit/bfab3fc226d8288f8bb1c7c6d1b13a49dbf23382))
* **release:** keep gh optional in analysis ([afe7dd3](https://github.com/starfysh-tech/nautilai/commit/afe7dd350ebdf18aa0298ba1fed69e76f00fabc1))
* **setup:** align local commit-msg hook with ci ([bfb2cb1](https://github.com/starfysh-tech/nautilai/commit/bfb2cb1a3a037ca56dce3309f5a0123cf4ab2ac4))
* **setup:** guard husky and ssh-keygen on missing tools ([bdf1730](https://github.com/starfysh-tech/nautilai/commit/bdf1730fbd752c675153dad10b25bddd2ea89f99))
* **setup:** harden branch-protection apply ([cd1e198](https://github.com/starfysh-tech/nautilai/commit/cd1e19800bf8fd34af845fe2bef529b61151ae7f))


### Documentation

* add github pages landing page ([85cbe17](https://github.com/starfysh-tech/nautilai/commit/85cbe1776ee54bc37ae5d3f0a6ad04af74e1717f))
* add GitHub Pages landing page ([df0b337](https://github.com/starfysh-tech/nautilai/commit/df0b337892544cae35ec2972727e940ba1149dba))
* redesign GitHub Pages landing page ([1e2899d](https://github.com/starfysh-tech/nautilai/commit/1e2899d42a0f2020cbae70249d81aeb1f078685f))
* redesign pages site with custom dark theme ([3493ded](https://github.com/starfysh-tech/nautilai/commit/3493ded5a789b3efd639a726631dc70ae32c2a3f))
* refine pages layout and spacing ([5489593](https://github.com/starfysh-tech/nautilai/commit/54895935d6248b3a68872f10e4dec54cddabd6db))
* refresh readme and align command syntax ([8564325](https://github.com/starfysh-tech/nautilai/commit/8564325f99be3419903716e1d68c2c2f297b1845))
