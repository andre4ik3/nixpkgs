# Performance Co-Pilot (PCP) {#module-services-performance-co-pilot-pcp}

[Performance Co-Pilot (PCP)][PCP] is a system performance analysis toolkit that
allows gaining insight into various system metrics. NixOS provides extensive
support for PCP through the `services.pcp` suite of options.

## Basic usage {#module-services-performance-co-pilot-pcp-basic-usage}

A basic, but functional PCP setup can be achieved with the following:

```nix
{
  services.pcp.enable = true;
}
```

By default, `pmcd` (the Performance Metrics Collector) collects local metrics
from a handful of PMDAs (Performance Metrics Domain Agents), and `pmlogger`
(the Performance Metrics Archiver) archives them for the past 24 hours.

Additional PMDAs are enabled on-demand, according to other NixOS options (such
as the `libvirt` PMDA when `virtualisation.libvirtd.enable` is true). In most
cases, no additional configuration is required to collect metrics from services
with PMDAs shipped with PCP.

If a graphical desktop environment is available, the Qt-based `pmcharts` (also
known as "PCP Charts") can be used to view all of the local machine's metrics.
Alternatively, [Cockpit](#module-services-cockpit) provides a simple web-based
graphical interface that shows CPU, Memory, Disk I/O, and Network metrics.

## Configuration {#module-services-performance-co-pilot-pcp-configuration}

TODO actual docs
TODO mpvis and stuff for pmview 3d stuff
TODO build without qt?

## References {#module-services-performance-co-pilot-pcp-references}

- The [PCP Guides][Guides] website provides a number of useful user,
  administrator, and programmer guides for working with PCP.
- The [PCP manual pages][Manual] are also available online, in addition to
  being shipped as part of the `pcp` package.

[PCP]: https://pcp.io
[Guides]: https://pcp.readthedocs.io/en/latest/
[Manual]: https://man7.org/linux/man-pages/dir_by_project.html#PCP

