# Reference

These pages are the specifications. They state what the product does, exactly and in full, and they guide the implementation: a change in behavior updates its spec in the same commit. Each spec ends with numbered testable behaviors, such as `TM-1`, and each of those is backed by a test that carries the identifier. Start with [Components](components.md), which names the parts, defines the vocabulary, and states the rules that cut across them.

The specs are written for looking things up. For a gentler account of the same features, see the [Explanation](../explanation/index.md) section.

```{toctree}
:caption: Overview
:maxdepth: 1

components
```

```{toctree}
:caption: Mac app
:maxdepth: 1

timer
menubar
projects
calendar
reports
activity
activity_tracking
```

```{toctree}
:caption: iPhone and iPad
:maxdepth: 1

ios
```

```{toctree}
:caption: Shared foundations
:maxdepth: 1

data_and_sync
automation
design
```

```{toctree}
:caption: Development
:maxdepth: 1

architecture
/xcode27
/contributing
```
