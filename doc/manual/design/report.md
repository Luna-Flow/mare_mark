# `report` Design

The report backend is a pure projection. JSON uses the core structured encoder;
SVG and HTML escape text and attributes before interpolation. No report function
touches the filesystem.

The renderer derives categories and series from points, computes padded dynamic
Y bounds, averages repeated category values only for connecting lines, and
retains every raw point as a tooltip-bearing mark. The HTML wrapper is
responsive and contains no remote assets.

Plot IR `x` remains categorical. Consequently, Pareto rendering is currently a
categorical scatter view rather than a numeric two-axis frontier. JSONL
projection currently creates one scaling plot and receives target as an
explicit argument.

